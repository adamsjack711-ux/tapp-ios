# Tapp — AppFusion collection

[← Tapp](../../README.md) · [Documentation](../README.md)

Tapp is an iPhone assistant that accepts a spoken request, opens the destination app, chooses screen actions, and checks the result. The AppFusion presentation focuses on a recorded request to open Spotify and search for “Daft Punk.” The category was Community and Accessibility.

## Explore

| Material | Location |
| --- | --- |
| Project presentation and gallery | [AppFusion front page](materials/README.md) |
| Editable four-slide pitch | [Tapp-AppFusion.pptx](materials/tapp/Tapp-AppFusion.pptx) |
| 20-second edited demonstration | [Spotify demo](materials/tapp/demo-footage/Tapp-In-Action-Refined-Split.mp4) |
| Original vertical phone capture | [Phone recording](materials/tapp/demo-footage/Tapp-Spotify-Phone-Capture.mp4) |
| Intro video | [Launch clip](materials/tapp/demo-footage/Tapp-Launch-1920x1080.mp4) |
| Recording and editing context | [Footage notes](materials/tapp/demo-footage/README.md) |
| Six app screenshots | [Gallery assets](materials/tapp/screenshots/) |
| Submission copy and device checklist | [Submission notes](materials/tapp/README.md) |
| Earlier presentation artwork | [Superseded artwork](archive/superseded-artwork/) |
| Verification and scope | [Status](STATUS.md) |

## Evidence and dates

The two Spotify recordings show the same October 30 physical iPhone run, before AppFusion. The submission notes report about 36 seconds in its source trace; the edited demo cuts waiting time. The November 23 screenshots show a simulator preview, including an unsent request.

The original notes report 956 Swift tests in 104 suites on the November 22 integration baseline `b4df7fb`. This is historical evidence, not a fresh test of the public source snapshot. The recorded checklist still requires final device checks for live voice, Spotify, connectivity, Stop, and incomplete input, plus confirmation of the exact voice and vision model identifiers.

## Preview and source branches

The historical [AppFusion simulator release](https://github.com/LALITH-GAUTAM/appfusion-hackathon/releases/tag/tapp-appfusion-preview) came from a separate private integration line at `b4caca991da147cbc50cb5d1a6cc88e3d696a954`. That release requires access to its private repository. It uses `Tapp.xcodeproj` and `com.jackadamslovell.Tapp`; this public source uses `PocketAgent.xcodeproj` and `com.jackadamslovell.PocketAgent`. Follow the [development guide](../DEVELOPMENT.md) for this checkout.

The hosted Tapp backend, earlier AppFusion backend prototype, operational audit records, and private Git history are excluded from this public repository. No beta access code is included. Historical submission notes retain their dates and context; they do not confirm final submission or judge access.
