import AppKit
import Carbon.HIToolbox

enum Clipboard {
    /// Write text to pasteboard and immediately post Cmd-V to the focused app.
    /// Unlike vvrite's approach, we do not restore the previous pasteboard contents —
    /// the transcribed text stays on the clipboard for later reuse.
    static func writeAndPaste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        Thread.sleep(forTimeInterval: 0.05)
        sendCmdV()
    }

    static func writeOnly(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func sendCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
