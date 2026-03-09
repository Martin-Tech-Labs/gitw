import Foundation
import Darwin

public enum TTY {
    public static func readLine(prompt: String) throws -> String {
        FileHandle.standardError.write(Data(prompt.utf8))
        guard let line = Swift.readLine() else { throw GitwError.io("stdin closed") }
        return line.trimmingCharacters(in: .newlines)
    }

    public static func readSecret(prompt: String) throws -> String {
        FileHandle.standardError.write(Data(prompt.utf8))

        var old = termios()
        if tcgetattr(STDIN_FILENO, &old) != 0 {
            // Not a TTY; fall back.
            guard let line = Swift.readLine() else { throw GitwError.io("stdin closed") }
            return line.trimmingCharacters(in: .newlines)
        }

        var new = old
        new.c_lflag &= ~UInt(ECHO)
        if tcsetattr(STDIN_FILENO, TCSANOW, &new) != 0 {
            throw GitwError.io("failed to disable echo")
        }
        defer { _ = tcsetattr(STDIN_FILENO, TCSANOW, &old) }

        guard let line = Swift.readLine() else { throw GitwError.io("stdin closed") }
        FileHandle.standardError.write(Data("\n".utf8))
        return line.trimmingCharacters(in: .newlines)
    }
}
