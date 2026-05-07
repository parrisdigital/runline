# Contributing

Thanks for helping improve Runline. This project is in public beta, so keep changes focused and easy to review.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## Development Setup

Requirements:

- macOS with Xcode capable of building the configured iOS target
- iOS 26+ simulator runtime for full local app testing
- Node.js 20+
- npm

Install bridge dependencies:

```bash
npm --prefix orchestrator install
```

Run bridge checks:

```bash
npm --prefix orchestrator run typecheck
npm --prefix orchestrator run build
```

Run iOS tests:

```bash
xcodebuild test \
  -project Runline.xcodeproj \
  -scheme Runline \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

## Pull Requests

- Keep UI changes native to SwiftUI and iOS system patterns.
- Keep Cloud Agent mode working without Runline Bridge.
- Keep Cursor SDK mode optional and clearly labeled as requiring Runline Bridge.
- Add or update tests for behavior changes.
- Do not commit generated archives, IPAs, derived data, local ASC artifacts, npm tokens, Apple signing material, API keys, or private repository data.
- Run `git diff --check`, bridge typecheck/build, and relevant iOS tests before opening a PR.

## Security

Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Do not disclose credentials or private repository data in public issues or pull requests.
