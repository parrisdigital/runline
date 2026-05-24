# Changelog

Runline is in public beta. Versions may move quickly while the iOS app, TestFlight flow, and public App Store experience settle.

## Unreleased

- Added a Fly-hosted Cursor SDK bridge for Cursor Chat.
- Split Cursor Chat and Cursor Cloud into separate navigation experiences.
- Added a conversational Cursor Chat start surface with a bottom composer, attachments, model picker, and separate repo/general-chat context selector.
- Set Cursor Chat to default to `composer-2.5` while retaining an explicit user model selection for later SDK workspace chats.
- Fixed Cursor Chat launch routing so SDK-backed sessions open as Cursor Chat conversations instead of falling through to Cursor Cloud.
- Changed Cursor Chat launches and conversation selections to swap in place instead of pushing a slide-over detail screen.
- Reduced quiet live-listener cache writes and clarified the SDK waiting state while Cursor Chat waits for streamed updates.
- Paused timeline auto-scroll during manual scrolling so live Cursor Chat updates do not fight the user's scroll gesture.
- Bounded Cursor Chat thinking/tool-call rendering with compact activity rows, a details sheet, cached timeline snapshots, and collapsed diff cards to prevent freezes during active runs.
- Refined Cursor Chat into a composer-first start screen with a Remodex-inspired slide-over conversation drawer, active sessions, grouped workspace conversations, and compact file-change, artifact, PR, model, and branch indicators.
- Seeded new launches and follow-ups with an immediate local user message so the detail screen opens as a conversation while Cursor events stream in.
- Added a durable Fly-volume session metadata store for Cursor Chat so SDK sessions can be listed and resumed after bridge restarts without persisting Cursor API keys or prompt text.
- Added queued Cursor Chat follow-ups while an SDK run is active so users can keep the conversation moving without cancelling the current run.
- Kept Cursor Cloud on the structured Cloud Agent launch and run-review flow.
- Added defensive SDK event payload preservation plus inline file-change cards and diff sheets when Cursor Chat streams diff data.
- Added Settings status and connection testing for Cursor Chat without requiring users to configure a bridge URL.
- Kept Cursor API keys in iOS Keychain and designed the bridge to use per-request keys without persistence.
- Updated public docs and contributor rules to distinguish backendless Cursor Cloud from SDK-backed Cursor Chat.

## TestFlight 1.0 (25)

- Refocused Runline as a Cursor Cloud-only iOS app.
- Removed the local service package, setup flow, pairing state, local-network permissions, camera permission, dedicated secondary runtime, and related tests.
- Redesigned navigation around Chats, Repositories, and Settings.
- Reworked chat detail into a message-first Cloud Agent conversation with refined status, context chips, run events, artifacts, and a bottom composer.
- Refined New Chat into an instructions-first composer with prompt starters, repository selection, model selection, attachments, and output controls.
- Removed the Cursor Automations surface so the app stays fully native after the user connects an API key.
- Updated public docs, contribution rules, security notes, issue templates, and CI checks for the Cloud-only product boundary.
- Uploaded build 25 to TestFlight and distributed it to the configured beta group.

## TestFlight 1.0 (21)

- Uploaded the previous beta build to TestFlight.
- Included native iPhone and iPad support for Cloud Agent chats, repositories, Settings, attachments, model selection, light/dark mode, and release-state documentation.
