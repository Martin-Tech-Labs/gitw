public enum AskpassTrust {
    /// Hardcoded SHA-256 of the trusted `gitw-askpass` binary.
    ///
    /// Rationale: we want a simple, fail-closed integrity check even when users
    /// sign with self-signed certificates (where verifying a stable identity may
    /// not be practical).
    ///
    /// Update procedure:
    ///   swift build -c release
    ///   .build/release/gitw print-askpass-hash
    public static let expectedAskpassSHA256 = "688787a6154832eadbe1126e835be7a25a701c3b88289cd80686629a40929555"
}
