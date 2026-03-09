import Foundation

public enum GitwError: Error, CustomStringConvertible {
    case usage(String)
    case denied(String)
    case keychain(String)
    case io(String)
    case signature(String)
    case git(String)

    public var description: String {
        switch self {
        case .usage(let s): return s
        case .denied(let s): return s
        case .keychain(let s): return s
        case .io(let s): return s
        case .signature(let s): return s
        case .git(let s): return s
        }
    }
}

public func die(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}
