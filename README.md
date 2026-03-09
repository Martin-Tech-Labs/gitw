# gitw

`gitw` is a **secure Git wrapper for macOS** that:

- Only allows **GitHub HTTPS** remotes (`https://github.com/...`).
- Stores GitHub credentials in the **macOS Keychain**.
- Runs `git` with an **in-memory ASKPASS broker** over a **Unix domain socket** (one-time token serve, with timeout).
- Disables Git credential helpers and forces `GIT_TERMINAL_PROMPT=0` (fail closed).
- Verifies `/usr/bin/git`’s **code signature** against a baked-in requirement string.

This is meant to reduce credential leakage and prevent accidental use of SSH / non-GitHub remotes.

## Build

```bash
cd gitw
swift build -c release
```

Binaries:

- `.build/release/gitw`
- `.build/release/gitw-askpass` (internal helper)

## Install (example)

```bash
sudo install -m 0755 .build/release/gitw /usr/local/bin/gitw
sudo install -m 0755 .build/release/gitw-askpass /usr/local/bin/gitw-askpass
```

(They should live in the same directory, unless you set `GITW_ASKPASS_PATH`.)

## Usage

### 1) Login (store a PAT in Keychain)

`login` **verifies** the token by running `git ls-remote` via the askpass broker and **only stores on success**.

```bash
gitw login https://github.com/OWNER/REPO.git
```

You’ll be prompted for:

- GitHub username
- GitHub Personal Access Token (PAT)

### 2) Use gitw like git

```bash
gitw clone https://github.com/OWNER/REPO.git
gitw fetch
gitw push
```

### 3) Inspect / remove credentials

```bash
gitw whoami
gitw logout
```

## Environment variables

- `GITW_NAME`, `GITW_EMAIL` (optional)
  - If set, `gitw` exports these as `GIT_AUTHOR_NAME/EMAIL` and `GIT_COMMITTER_NAME/EMAIL`.

- `GITW_ASKPASS_PATH`
  - Override the path to `gitw-askpass`.


## Code signature verification

By default, `gitw` runs **only** `/usr/bin/git` and requires it to satisfy:

- `identifier "com.apple.dt.xcode_select.tool-shim-public" and anchor apple`

To see the designated requirement for a given binary:

```bash
codesign -dr - /path/to/git 2>&1
```


## Security notes / design

- Credentials are stored only in the **macOS Keychain** (`kSecClassInternetPassword`, server `github.com`).
- For each `gitw` invocation, credentials are provided to git via an **ASKPASS broker**:
  - Broker listens on a per-run Unix domain socket in a 0700 temp directory.
  - Client must present a random nonce.
  - Only serves username once + token once.
  - Socket is removed on exit and has a short timeout.
- Git is run with:
  - `GIT_TERMINAL_PROMPT=0`
  - `credential.helper=` (disabled via `GIT_CONFIG_COUNT`)
  - `credential.useHttpPath=true`
- URL policy denies:
  - `ssh://`, `git://`, `http://`
  - `git@...` / scp-style URLs
  - non-`github.com` hosts
  - credential-bearing URLs

**Fail closed:** if git tries to prompt, it won’t; and if askpass isn’t configured (no creds), auth will fail rather than falling back to interactive prompts.

## Limitations

- This is intentionally restrictive: it’s for GitHub-over-HTTPS only.
- Some git subcommands may involve complex URL expansion; `gitw` only validates arguments it can see.
