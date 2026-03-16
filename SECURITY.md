# Security

## Threat model

`gitw` is designed for environments where the account running automation (e.g. an agent user) is **not fully trusted**, but the installation prefix (e.g. `/usr/local/bin`) and the OS admin/root account are trusted.

### We aim to protect against

- Accidental or malicious use of non-GitHub remotes.
- SSH-based Git URLs (`git@…`) and non-HTTPS remotes.
- Git credential helpers storing or retrieving secrets implicitly.
- Token leakage via argv, files, or long-lived helper processes.

### Non-goals

- If **admin/root** is compromised, `gitw` cannot meaningfully protect secrets.
- A process already running with the same privileges as the user invoking `gitw` can always run its own tools; `gitw` focuses on making the *Git invocation* fail closed and reducing accidental leakage.

## Key design points

- `/usr/bin/git` only: no PATH lookups; code signature is checked against a baked-in requirement.
- Credentials at rest live in **macOS Keychain**.
- Authentication uses Git’s `GIT_ASKPASS` mechanism via `gitw-askpass`, but the token is served by a short-lived in-memory broker over a **Unix domain socket**.
- A per-run **nonce** binds askpass requests to the broker.
- Helpers are disabled and prompting is blocked (`GIT_TERMINAL_PROMPT=0`).

## Keychain schema

- `--as <alias>` selects a local alias.
- Keychain `kSecAttrAccount` = alias
- Keychain `kSecAttrComment` = actual GitHub username (used for HTTP auth)
- Keychain secret data = token

## CI notes

GitHub Actions runners may have a differently signed `/usr/bin/git` than your local system. CI can opt out of `/usr/bin/git` signature checking in DEBUG builds using `GITW_SKIP_GIT_SIGNATURE_CHECK=1`.

Release builds always enforce signature policy.
