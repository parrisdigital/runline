# Releases

This document is the maintainer checklist for GitHub, npm, and TestFlight releases.

## Current Public State

| Surface | State |
| --- | --- |
| GitHub repository | Public at `https://github.com/parrisdigital/runline` |
| License | MIT |
| iOS bundle ID | `com.matthewparris.runline` |
| iOS marketing version | `1.0` |
| Local project build number | `18` in `project.yml` |
| TestFlight | Runline `1.0 (18)` is in internal and external beta testing |
| npm package | `runline-bridge@0.1.5` published |
| npm dist-tags | `latest` -> `0.1.5`, `beta` -> `0.1.5` |
| GitHub releases | Source beta `v1.0.0-beta.1`; latest TestFlight marker `testflight-1.0-18`; historical TestFlight release `testflight-1.0-6` |

The stale draft GitHub release for build 24 was removed. Use explicit build numbers for every TestFlight upload so App Store Connect, GitHub notes, and the local project stay aligned.

## Pre-Release Checks

Run these from the repository root:

```bash
git status --short
git diff --check
npm --prefix orchestrator run typecheck
npm --prefix orchestrator run build
npm --prefix orchestrator audit --audit-level=high
gitleaks detect --source . --redact --verbose
gitleaks detect --source . --no-git --redact --verbose
xcodebuild test -project Runline.xcodeproj -scheme Runline -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'
```

Review public-boundary docs before source releases:

- [SELF_HOSTING_MODEL.md](../SELF_HOSTING_MODEL.md)
- [docs/self-hosting.md](self-hosting.md)
- [AGENTS.md](../AGENTS.md)
- [Legal/TRADEMARKS.md](../Legal/TRADEMARKS.md)

For a faster metadata-only check:

```bash
xcodebuild -list -project Runline.xcodeproj
ruby -c Tools/set_build_number.rb
plutil -lint ExportOptions-AppStore.plist ExportOptions-TestFlightUpload.plist Runline/Resources/Info.plist Runline/Resources/PrivacyInfo.xcprivacy Runline/Resources/Runline.entitlements
```

## GitHub Release

Use GitHub releases for public source milestones and important TestFlight markers.

Recommended source beta tag format:

```bash
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
gh release create v1.0.0-beta.1 \
  --repo parrisdigital/runline \
  --prerelease \
  --title "Runline Public Beta" \
  --notes-file /tmp/runline-public-beta.md
```

Recommended TestFlight tag format:

```text
testflight-1.0-<build-number>
```

Do not attach IPAs, archives, signing files, `.p8` keys, provisioning profiles, or local ASC artifacts to public releases.

## npm Release

`runline-bridge` lives in `orchestrator/`.

Before publishing:

```bash
npm --prefix orchestrator install
npm --prefix orchestrator run typecheck
npm --prefix orchestrator run build
npm --prefix orchestrator audit --audit-level=high
npm --prefix orchestrator pack --dry-run
```

Patch release:

```bash
cd orchestrator
npm version patch --no-git-tag-version
npm publish --tag beta
npm dist-tag add runline-bridge@<version> latest
```

If npm reports `EOTP` for an account that uses a passkey or security key instead of authenticator codes, rerun the protected write with browser authentication:

```bash
npm publish --tag beta --auth-type=web
npm dist-tag add runline-bridge@<version> latest --auth-type=web
```

After publish:

```bash
npm view runline-bridge version dist-tags versions repository.url homepage bugs.url license description --json
npm install -g runline-bridge@latest
runline-bridge --version
```

Commit the package version, shrinkwrap, and documentation updates after a successful publish.

## TestFlight Release

The ASC workflow is maintainer-only. It expects a local App Store Connect profile named `Runline` and private credentials stored outside git.

Create the local workflow from the sanitized example:

```bash
cp .asc/workflow.example.json .asc/workflow.json
```

Fill in the local App Store Connect app ID, bundle ID, and TestFlight group IDs. The live `.asc/workflow.json` file is ignored by git and must not be committed.

Preflight:

```bash
asc workflow run preflight
```

Upload and distribute with an explicit build number:

```bash
asc workflow run testflight BUILD_NUMBER:<next-build-number>
```

Distribute an already uploaded build:

```bash
asc workflow run distribute-existing BUILD_NUMBER:<build-number>
```

Use the next intentional build number, not the local `CURRENT_PROJECT_VERSION`, if TestFlight/App Store Connect has a different latest visible build.

## Release Notes Template

```text
Runline <version> (<build>)

- Cloud Agent mode remains the default native iOS path.
- Cursor SDK mode remains optional through Runline Bridge.
- Tested on iPhone and iPad layouts.
- Bridge package: runline-bridge@<version>.
- Security checks: npm audit and gitleaks passed.
```

## Security Checklist

- No `.env`, `.npmrc`, `.p8`, `.p12`, `.mobileprovision`, `.ipa`, `.xcarchive`, private key, certificate, or ASC artifact is tracked.
- No live `.asc/workflow.json` maintainer config is tracked.
- Only safe examples such as `.asc/workflow.example.json` and `orchestrator/.env.example` are tracked.
- `gitleaks detect --source . --redact --verbose` passes.
- `gitleaks detect --source . --no-git --redact --verbose` passes.
- npm package contents are checked with `npm pack --dry-run`.
- TestFlight artifacts remain in `.asc/artifacts/` and are ignored by git.
- Cursor and Apple credentials are rotated immediately if they are ever exposed.
