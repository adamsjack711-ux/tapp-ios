"""Count offline audit text with o200k_base; these are NOT provider-billed usage.

Usage: python count-audit-tokens.py payloads.json report.json
Requires tiktoken. No API key, phone, or model inference is used.
"""
import json
import sys
import tiktoken

encoding = tiktoken.get_encoding("o200k_base")


def tokens(value):
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return len(encoding.encode(text, disallowed_special=()))


reports = json.load(open(sys.argv[1]))
for report in reports:
    details = []
    for number, call in enumerate(report.pop("calls"), 1):
        request = call["request"]
        messages = request.get("messages", request.get("input"))
        response = call["scripted_response"]
        details.append({
            "call": number,
            "next_step": response.get("tool_calls", [{}])[0].get("function", {}).get("name", "final_answer"),
            "system_text_tokens": sum(tokens(m["content"]) for m in messages if m.get("role") == "system"),
            "tool_schema_json_tokens": tokens(request.get("tools", [])),
            "conversation_json_tokens": tokens([m for m in messages if m.get("role") != "system"]),
            "estimated_input_payload_tokens": tokens({"input" if "input" in request else "messages": messages, "tools": request.get("tools", [])}),
            "scripted_output_json_tokens": tokens(response),
            "output_token_cap": request.get("max_tokens", request.get("max_output_tokens")),
        })
    report["model_calls"] = len(details)
    report["estimated_input_payload_tokens"] = sum(d["estimated_input_payload_tokens"] for d in details)
    report["scripted_output_json_tokens"] = sum(d["scripted_output_json_tokens"] for d in details)
    report["per_call"] = details

output = {
    "measurement": "Offline serialized-text token estimates, NOT live API usage or billing",
    "encoding": "o200k_base (proxy; no gpt-6.1-sol tokenizer mapping available)",
    "limitations": [
        "Model decisions and outputs are scripted; this does not measure model accuracy or latency.",
        "Fresh conversations; synthetic short OCR screens; task-scoped tools on the optimized path.",
        "Provider chat/function formatting overhead, cached-token accounting and reasoning tokens are not measured.",
        "The output cap is a maximum, not tokens consumed. Scripted output is not a prediction of real output length.",
        "History now retains at most two earlier user turns and 24 KiB of prior context; active tasks can still grow.",
    ],
    "scenarios": reports,
}
with open(sys.argv[2], "w") as handle:
    json.dump(output, handle, indent=2)
for report in reports:
    print(f'{report["scenario"]:28} {report["version"]:10} calls={report["model_calls"]} input~{report["estimated_input_payload_tokens"]} scripted_output={report["scripted_output_json_tokens"]}')
