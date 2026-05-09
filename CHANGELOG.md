# Changelog

All notable public changes to Runline are tracked here.

Runline is in public beta. Versions may move quickly while the iOS app, TestFlight flow, and optional Cursor SDK bridge settle.

## Unreleased

- Keep Cloud Agent mode as the default iOS experience.
- Continue refining Cursor SDK mode and Runline Bridge pairing for power users.
- Improve iPhone and iPad polish while staying native to SwiftUI and iOS system patterns.
- Refined Cursor SDK onboarding into shorter native pages with a fixed bottom action area and a Standard/Keep Awake bridge start option.
- Added public self-hosting, bridge setup, trademark, environment example, and coding-agent guidance.
- Refined post-API-key onboarding with an inline Cursor SDK bridge setup, pairing, and connection check flow.
- Added a native SDK Tools experience for inspecting bridge-published MCP servers, tools, skills, hooks, and subagents from Settings, New Chat, and SDK chats.

## runline-bridge 0.1.4

- Published `runline-bridge@0.1.4` to npm.
- Set both `latest` and `beta` npm dist-tags to `0.1.4`.
- Added `runline-bridge up --keep-awake`, backed by macOS `caffeinate`.
- Added bridge health metadata for whether Keep Awake is active.

## TestFlight Build 1.0 (16)

- Prepared the next TestFlight build with the unified Cursor SDK onboarding layout.
- Made the SDK onboarding pages and footer controls behave as one continuous native sheet instead of a separate bottom inset.
- Kept the page dots and button styling while reducing the overlap/scroll feeling on the initial Cursor SDK page.
- Preserved text sizing and tightened only spacing and card padding.

## TestFlight Build 1.0 (15)

- Uploaded the API-key-aware Cursor SDK onboarding refinement to TestFlight.
- Added Cursor API Key status directly inside SDK setup so users can see Keychain state or connect a missing key.
- Kept Cloud Agent mode as the default and Cursor SDK mode as an optional bridge-powered flow.

## TestFlight Build 1.0 (14)

- Uploaded the refined Cursor SDK onboarding and Keep Awake build to TestFlight.
- Submitted and received approval for external TestFlight beta testing.
- Includes the shorter native SDK onboarding pages, fixed bottom action bar, and Standard/Keep Awake bridge start option.

## runline-bridge 0.1.3

- Published `runline-bridge@0.1.3` to npm.
- Set both `latest` and `beta` npm dist-tags to `0.1.3`.
- Prepared richer SDK profile metadata for MCP servers, tool hints, skills, hooks, and subagents.
- Kept bridge-side MCP credentials, command environments, hook scripts, and full subagent prompts out of iOS metadata responses.

## TestFlight Build 1.0 (13)

- Uploaded the native SDK Tools workspace build to TestFlight.
- Added the valid processed build to the configured beta group.
- Submitted and received approval for external TestFlight beta testing.
- Includes native SDK profile inspection for MCP servers, tools, skills, hooks, and subagents across Settings, New Chat, and SDK chats.

## Runline Public Beta

- Renamed the project and repository to Runline.
- Prepared GitHub source release `v1.0.0-beta.1`.
- Moved the public repository to `https://github.com/parrisdigital/runline`.
- Preserved the App Store bundle identifier `com.matthewparris.runline`.
- Added open source project files: MIT license, security policy, contributing guide, support guide, code of conduct, issue templates, PR template, Dependabot, CI, and gitleaks configuration.
- Added native iPhone and iPad support for Cloud Agent chats, repositories, Settings, attachments, model selection, light/dark mode, and optional Cursor SDK mode.
- Cleaned chat event rendering so streaming text and thinking deltas are grouped into readable timeline entries.

## runline-bridge 0.1.2

- Published `runline-bridge@0.1.2` to npm.
- Set both `latest` and `beta` npm dist-tags to `0.1.2`.
- Updated npm metadata to point to `parrisdigital/runline`.
- Preserved Cursor SDK session endpoints, pairing endpoints, MCP profile metadata, and Cloud compatibility aliases.
- Added dependency overrides and shrinkwrap updates so the local bridge audit passes with no high-severity findings.

## runline-bridge 0.1.1

- Prepared the bridge package for public beta usage.
- Added repository, homepage, bugs, license, keywords, and packaged README metadata.
- Tightened npm package contents to the CLI, compiled output, README, and shrinkwrap.

## runline-bridge 0.1.0

- Initial bridge package for optional Cursor SDK sessions.
- Added local server, health check, pairing, SDK session creation, follow-up messages, session state, and event endpoints.

## TestFlight Build 1.0 (6)

- Historical TestFlight prerelease retained on GitHub as `testflight-1.0-6`.
- Included iPad adaptive layout work and native iPhone/iPad validation.

## Notes

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.
