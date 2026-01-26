//
//  TerminalSize.swift
//  AISDKCLI
//
//  Terminal dimension utilities
//

import Foundation

/// Terminal size information
struct TerminalSize {
    let width: Int
    let height: Int

    /// Get current terminal size
    static func current() -> TerminalSize {
        var w = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
            return TerminalSize(width: Int(w.ws_col), height: Int(w.ws_row))
        }
        // Default fallback
        return TerminalSize(width: 80, height: 24)
    }

    /// Check if output is a TTY (interactive terminal)
    static var isTTY: Bool {
        isatty(STDOUT_FILENO) != 0
    }

    /// Check if input is a TTY
    static var isInputTTY: Bool {
        isatty(STDIN_FILENO) != 0
    }
}

/// Raw terminal mode for capturing individual keystrokes
class RawTerminalMode {
    private var originalTermios: termios?
    private var isRaw = false

    /// Enable raw mode (disable line buffering, echo)
    func enable() {
        guard !isRaw else { return }

        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        // Disable canonical mode (line buffering) and echo
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)

        // Set minimum characters for read
        raw.c_cc.4 = 1  // VMIN - minimum 1 character
        raw.c_cc.5 = 0  // VTIME - no timeout

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRaw = true
    }

    /// Disable raw mode (restore original settings)
    func disable() {
        guard isRaw, var original = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        isRaw = false
    }

    deinit {
        disable()
    }
}

/// Key codes for special keys
enum KeyCode: Equatable {
    case char(Character)
    case up
    case down
    case left
    case right
    case enter
    case backspace
    case delete
    case tab
    case escape
    case home
    case end
    case pageUp
    case pageDown
    case ctrlC
    case ctrlD
    case ctrlL
    case unknown(Int)

    /// Read a key from stdin in raw mode
    static func read() -> KeyCode? {
        var buffer = [UInt8](repeating: 0, count: 4)
        let bytesRead = Foundation.read(STDIN_FILENO, &buffer, buffer.count)

        guard bytesRead > 0 else { return nil }

        // Single byte characters
        if bytesRead == 1 {
            let byte = buffer[0]

            switch byte {
            case 0x03: return .ctrlC
            case 0x04: return .ctrlD
            case 0x09: return .tab
            case 0x0A, 0x0D: return .enter
            case 0x0C: return .ctrlL
            case 0x1B: return .escape
            case 0x7F: return .backspace
            default:
                if byte >= 0x20 && byte < 0x7F {
                    return .char(Character(UnicodeScalar(byte)))
                }
                return .unknown(Int(byte))
            }
        }

        // Escape sequences (arrow keys, etc.)
        if bytesRead >= 3 && buffer[0] == 0x1B && buffer[1] == 0x5B {
            switch buffer[2] {
            case 0x41: return .up      // ESC [ A
            case 0x42: return .down    // ESC [ B
            case 0x43: return .right   // ESC [ C
            case 0x44: return .left    // ESC [ D
            case 0x48: return .home    // ESC [ H
            case 0x46: return .end     // ESC [ F
            case 0x33:
                if bytesRead >= 4 && buffer[3] == 0x7E {
                    return .delete     // ESC [ 3 ~
                }
            case 0x35:
                if bytesRead >= 4 && buffer[3] == 0x7E {
                    return .pageUp     // ESC [ 5 ~
                }
            case 0x36:
                if bytesRead >= 4 && buffer[3] == 0x7E {
                    return .pageDown   // ESC [ 6 ~
                }
            default:
                break
            }
        }

        // Try to decode as UTF-8 character
        if let str = String(bytes: buffer.prefix(bytesRead), encoding: .utf8),
           let char = str.first {
            return .char(char)
        }

        return .unknown(Int(buffer[0]))
    }
}
