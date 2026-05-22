# Release Checklist

This document is for maintainers preparing TestFlight, App Store, and public GitHub releases.

Runline is a Cursor Cloud-only iOS app. Release work should not introduce required hosted services or private endpoints.

## Current Release State

| Area | State |
| --- | --- |
| iOS app | Runline `1.0 (21)` in beta sequence |
| Runtime | Direct Cursor Cloud Agents API |
| Public source | Safe to build without maintainer credentials |
| ASC config | Live `.asc/workflow.json` remains local and ignored |

## Local Preflight

Run these before public-facing release work:

```bash
git diff --check
gitleaks detect --source . --redact --verbose
xcodebuild test -project Runline.xcodeproj -scheme Runline -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
xcodebuild -list -project Runline.xcodeproj
ruby -c Tools/set_build_number.rb
plutil -lint ExportOptions-AppStore.plist ExportOptions-TestFlightUpload.plist Runline/Resources/Info.plist Runline/Resources/PrivacyInfo.xcprivacy Runline/Resources/Runline.entitlements
```

For deeper public-release checks:

```bash
gitleaks detect --source . --no-git --redact --verbose
```

## Build Number

Use explicit TestFlight build numbers.

Update build numbers through the project files and keep these in sync:

- `project.yml`
- `Runline.xcodeproj/project.pbxproj`
- `CHANGELOG.md`
- this release document when the public state changes

## TestFlight

Local ASC automation expects a private `Runline` App Store Connect profile in the maintainer's keychain.

Create local config from the sanitized example:

```bash
cp .asc/workflow.example.json .asc/workflow.json
```

Fill in local App Store Connect app and group IDs. Keep `.asc/workflow.json` ignored.

Run preflight:

```bash
asc workflow run preflight
```

Upload with an explicit build number:

```bash
asc workflow run testflight BUILD_NUMBER:<next-build-number>
```

## App Store Review Notes

Keep review notes clear and public-safe:

- Runline is an independent client for Cursor Cloud Agents.
- Users provide their own Cursor API key.
- Cursor API keys are stored in Keychain.
- Cursor bills usage through the user's Cursor account.
- Runline is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

Do not include private maintainer IDs, Apple API keys, signing files, live ASC workflow config, archives, IPAs, or private endpoints in public issues or releases.

## GitHub Release

Public GitHub releases should include source notes only.

Do not attach:

- `.ipa` files
- `.xcarchive` files
- signing certificates
- provisioning profiles
- live ASC artifacts
- local secrets or environment files

## Public Source Gate

Before opening or publishing source, confirm:

- `.asc/workflow.json` is ignored and absent from the diff.
- no Cursor API keys, Apple credentials, APNs credentials, or private repository data are present.
- generated archives, IPAs, and Xcode result bundles are absent.
- docs describe the Cloud-only runtime accurately.
- the non-affiliation disclaimer is present in app-facing docs.
