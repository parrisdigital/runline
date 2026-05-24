# Public Repo Model

This file explains what the public Runline repository is for, what it includes, and what it intentionally does not include.

Runline's default runtime path is backendless: the iOS app talks directly to Cursor's Cloud Agents API using the user's Cursor API key.

Runline also includes SDK-backed Cursor Chat bridge source under `Services/cursor-sdk-bridge` for auditability and maintainer deployment. Official beta builds can include a maintainer-configured bridge endpoint, but the public source does not publish the live bridge URL. Normal iOS users and contributors do not need npm, Node, Fly, or a local bridge for Cursor Cloud.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## What the Public Repo Includes

The public repository includes:

- the native iOS and iPadOS app source
- Cursor Cloud Agent client, models, providers, and tests
- the Cursor SDK bridge source used by the hosted Cursor Chat runtime
- release, contribution, security, support, and roadmap documentation
- a sanitized App Store Connect workflow example
- public design assets used by the app

The source tree is meant to be buildable and inspectable without private hosted infrastructure.

## What the Public Repo Does Not Include

The public repository does not include:

- private App Store Connect app IDs or TestFlight group IDs
- Apple API keys, signing certificates, provisioning profiles, archives, or IPAs
- private Cursor API keys
- private Fly tokens, bridge shared secrets, live `fly.toml`, or deployment credentials
- private bridge URLs or build settings that point at live infrastructure
- private APNs credentials
- private deployment defaults

Those values belong in local ignored config, Keychain, private CI settings, or maintainer-only release systems.

## Cloud Agent Runtime

In the Cloud Agent runtime:

- the iOS app stores the user's Cursor API key in Keychain
- the iOS app calls Cursor's Cloud Agents API directly
- no Runline backend is required
- no local service install is required
- no private Runline endpoint is required

This is the intended path for TestFlight users, App Store users, and public-source contributors.

## Optional Cursor Chat Runtime

In the Cursor Chat runtime:

- the iOS app keeps the user's Cursor API key in Keychain
- the iOS app sends the key over HTTPS to the configured SDK bridge only for SDK requests
- the bridge uses `@cursor/sdk` to create, resume, stream, and cancel Cursor cloud sessions
- the bridge is designed not to persist Cursor API keys
- hosted or self-hosted Fly deployments can mount a `/data` volume and set `RUNLINE_BRIDGE_SESSION_STORE_PATH` so session metadata survives Machine restarts
- self-hosted bridges can use an optional shared secret to prevent random public access
- the bridge exposes redacted SDK event-shape snapshots for validation; these snapshots record event types, field names, and structural types, not prompt text, file contents, artifact URLs, or API keys

The bridge's durable session store is intentionally metadata-only: session IDs, Cursor agent IDs, run IDs, repo/model metadata, run status, timing, and PR metadata. Prompt text and Cursor API keys stay out of bridge persistence.

The iOS app must continue to work when the bridge is absent or offline by keeping Cursor Cloud available.

## Why the Repo Stays Generic

The public repo stays generic so users can inspect and run the iOS app without being silently tied to a private service.

That means:

- Cursor Cloud requests remain direct from iOS.
- official beta builds may include a maintainer-configured Cursor Chat bridge endpoint; public-source builds keep that endpoint out of git and can provide it through `RUNLINE_SDK_BRIDGE_URL`
- public source does not contain private bridge secrets, private deployment config, or private credentials
- public source contains `fly.example.toml`, not live Fly app configuration
- local release automation uses examples instead of live maintainer config
- contributors can audit what the app does with Cursor API keys

Official TestFlight or App Store releases may use private signing and release configuration, but those values must stay outside the public repository.

## What to Keep Private

Keep these out of Git:

- Cursor API keys
- Fly tokens, bridge shared secrets, live `fly.toml`, and private deployment config
- Apple API keys and signing assets
- APNs keys and certificates
- `.asc/workflow.json`
- `.env` and `.npmrc`
- generated archives and IPAs

The short version: the public repo should be enough to build and inspect the app. Private release and account values stay private.
