# Security Policy

Runline is a public beta project. Please report security issues privately before opening a public issue.

## Supported Versions

Security fixes target:

- the latest commit on `main`
- the latest TestFlight beta build

Older TestFlight builds may be unsupported during beta.

## Reporting a Vulnerability

Email `parrisdigital@gmail.com` with:

- a clear description of the issue
- affected app or repository version
- reproduction steps
- expected impact
- any logs or screenshots that do not contain secrets

Do not include Cursor API keys, Apple credentials, GitHub tokens, private repository contents, private prompts, or artifact URLs in public issues.

## Credential Handling

- Cursor API keys are stored on iOS in Keychain.
- Cursor Cloud Agent requests are made directly from the device to Cursor's API.
- The repository must not contain `.p8`, `.p12`, `.mobileprovision`, `.env`, `.npmrc`, private keys, or signing certificates.

If a credential is ever committed, revoke and rotate it before opening the repository publicly.
