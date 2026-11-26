import Combine
import MessageUI
import SwiftUI

@MainActor
final class MessageComposeModel: ObservableObject {
    static let shared = MessageComposeModel()
    @Published var request: MessageRequest?
    @Published private(set) var result = "No message prepared."
    private var controller: MFMessageComposeViewController?

    func prepare(_ draft: MessageRequest) throws {
        guard request == nil else { throw MessageRequestError.busy }
        guard MFMessageComposeViewController.canSendText() else { throw MessageRequestError.unavailable }
        request = draft
        result = "Prepared one message to \(draft.recipientName). Nothing sent."
    }

    func attach(_ controller: MFMessageComposeViewController) { self.controller = controller }

    func finished(_ outcome: MessageComposeResult) {
        switch outcome {
        case .sent: result = "iOS accepted the message for sending. This is not a delivery receipt. Do not send it again."
        case .cancelled: result = "Message cancelled. Nothing sent by this flow."
        case .failed: result = "iOS reported a sending failure. Inspect Messages before retrying."
        @unknown default: result = "Unknown message result. Inspect Messages; do not retry Send."
        }
        controller = nil; request = nil
    }

    func dismissed() {
        if request != nil { result = MessageRequestError.interrupted.localizedDescription }
        controller = nil; request = nil
    }
}

struct MessageComposeSheet: UIViewControllerRepresentable {
    let draft: MessageRequest
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [draft.phone]
        controller.body = draft.body
        controller.disableUserAttachments()
        controller.messageComposeDelegate = context.coordinator
        MessageComposeModel.shared.attach(controller)
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    @MainActor
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            let rawResult = result.rawValue
            Task { @MainActor in
                MessageComposeModel.shared.finished(MessageComposeResult(rawValue: rawResult) ?? .failed)
            }
        }
    }
}
