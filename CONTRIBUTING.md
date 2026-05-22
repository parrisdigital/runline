# Contributing

Thanks for helping improve Runline. This project is in public beta, so keep changes focused and easy to review.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## Development Setup

Requirements:

- macOS with Xcode capable of building the configured iOS target
- iOS 26+ simulator runtime for full local app testing
- Swift 6
- XcodeGen, if regenerating `Runline.xcodeproj` from `project.yml`

Run iOS tests:

```bash
xcodebuild test \
  -project Runline.xcodeproj \
  -scheme Runline \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

Run metadata checks:

```bash
xcodebuild -list -project Runline.xcodeproj
ruby -c Tools/set_build_number.rb
plutil -lint ExportOptions-AppStore.plist ExportOptions-TestFlightUpload.plist Runline/Resources/Info.plist Runline/Resources/PrivacyInfo.xcprivacy Runline/Resources/Runline.entitlements
```

## Pull Requests

- Keep UI changes native to SwiftUI and iOS system patterns.
- Keep the Cursor Cloud Agent path working with only a user API key.
- Add or update tests for behavior changes.
- Do not commit generated archives, IPAs, derived data, local ASC artifacts, Apple signing material, API keys, or private repository data.
- Run `git diff --check`, secret scanning, and relevant iOS tests before opening a PR.
- For release process changes, update [docs/RELEASES.md](docs/RELEASES.md) and [CHANGELOG.md](CHANGELOG.md).
- Follow [AGENTS.md](AGENTS.md) for repository operating rules and [Legal/TRADEMARKS.md](Legal/TRADEMARKS.md) for branding boundaries.

## Security

Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Do not disclose credentials or private repository data in public issues or pull requests.
