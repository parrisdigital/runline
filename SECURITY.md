# Security Policy

Runline is a public beta project. Please report security issues privately before opening a public issue.

## Supported Versions

Security fixes target:

- the latest commit on `main`
- the latest TestFlight beta build
- the latest published `runline-bridge` npm package

Older TestFlight builds and old npm package versions may be unsupported during beta.

## Reporting a Vulnerability

Email `parrisdigital@gmail.com` with:

- a clear description of the issue
- affected app, bridge, or repository version
- reproduction steps
- expected impact
- any logs or screenshots that do not contain secrets

Do not include Cursor API keys, Apple credentials, npm tokens, GitHub tokens, private repository contents, or bridge pairing tokens in public issues.

## Credential Handling

- Cursor API keys are stored on iOS in Keychain.
- Runline Bridge pairing tokens are stored on iOS in Keychain.
- Runline Bridge accepts a Cursor API key per request or from `CURSOR_API_KEY` in the user's local environment.
- Runline Bridge must not store or log user Cursor API keys.
- The repository must not contain `.p8`, `.p12`, `.mobileprovision`, `.env`, `.npmrc`, private keys, or signing certificates.

If a credential is ever committed, revoke and rotate it before opening the repository publicly.
