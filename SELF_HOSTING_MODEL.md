# Public Repo and Self-Hosting Model

This file explains what the public Runline repository is for, what it includes, and what it intentionally does not include.

Runline has two runtime paths:

- Cloud Agent mode, which talks directly from the iOS app to Cursor's Cloud Agents API.
- Cursor SDK mode, which is optional and uses a user-controlled Runline Bridge.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## What the Public Repo Includes

The public repository includes:

- the native iOS and iPadOS app source
- the optional `runline-bridge` npm package source
- local pairing and bridge setup documentation
- release, contribution, security, and support documentation
- a sanitized App Store Connect workflow example
- public design assets used by the app

The source tree is meant to be usable without private hosted infrastructure baked into it.

## What the Public Repo Does Not Include

The public repository does not include:

- a private hosted bridge endpoint
- private App Store Connect app IDs or TestFlight group IDs
- Apple API keys, signing certificates, provisioning profiles, archives, or IPAs
- npm tokens or publish credentials
- private Cursor API keys
- private MCP server credentials
- private APNs credentials
- private deployment defaults

Those values belong in local environment variables, local ignored config, Keychain, private CI settings, or a separate private deployment repository.

## Cloud Agent Mode

Cloud Agent mode is the default path.

In this mode:

- the iOS app stores the user's Cursor API key in Keychain
- the iOS app calls Cursor's Cloud Agents API directly
- no Runline backend is required
- no Node.js install is required
- no Mac bridge is required

This is the intended default for TestFlight users and most beta usage.

## Cursor SDK Mode

Cursor SDK mode is optional.

In this mode:

- the user installs `runline-bridge`
- the bridge runs on the user's Mac or trusted server
- the iOS app pairs with that bridge
- trusted pairing can survive bridge restarts through a local bridge token file
- SDK sessions, MCP profile metadata, and SDK event streams flow through the bridge
- the user's Cursor API key can be passed per request or provided locally to the bridge

The public source does not ship with a hosted production bridge. Users who want bridge mode must run or host the bridge themselves.

## Self-Hosting Paths

Supported public-repo paths:

1. Simulator development with `http://localhost:8787`.
2. Physical iPhone on the same network using a Mac LAN URL such as `http://192.168.1.10:8787`.
3. Private-network setup through Tailscale or a similar tool.
4. Temporary HTTPS testing through a tunnel such as Cloudflare Tunnel.
5. A trusted HTTPS bridge or reverse proxy that the user operates.

When a bridge is exposed through a tunnel, reverse proxy, or hosted endpoint, `runline-bridge up --public-url <https-url>` should be used so the setup and pairing QR codes point at the reachable address.

For details, see [docs/self-hosting.md](docs/self-hosting.md).

## Why the Repo Stays Generic

The public repo stays generic so users can inspect and run the system without being silently tied to a private service.

That means:

- Cloud Agent mode remains direct from iOS.
- SDK mode remains explicitly optional.
- public source does not contain private hosted endpoints
- local release automation uses examples instead of live maintainer config
- contributors can audit what the app and bridge do

Official TestFlight builds or future hosted services may use private operational configuration, but those values must stay outside the public repository.

## What to Keep Private

Keep these out of Git:

- real bridge hostnames that should not be public
- private VPS IP addresses
- Cursor API keys
- Apple API keys and signing assets
- npm tokens
- APNs keys and certificates
- `.asc/workflow.json`
- `.env` and `.npmrc`
- private MCP credentials
- generated archives and IPAs

The short version: the public repo should be enough to build, inspect, and self-host. Private release and deployment values stay private.
