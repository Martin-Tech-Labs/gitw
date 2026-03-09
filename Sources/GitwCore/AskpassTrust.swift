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
    public static let expectedAskpassSHA256 = "be2fbaec374da7d6dbdcbf5096edd7e9932c1b30cc04a58cd2bc95aced0d21f4"
}
