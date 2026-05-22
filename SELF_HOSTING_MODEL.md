# Public Repo Model

This file explains what the public Runline repository is for, what it includes, and what it intentionally does not include.

Runline has one runtime path: the iOS app talks directly to Cursor's Cloud Agents API using the user's Cursor API key.

Runline is independent and is not affiliated with, endorsed by, or connected to Cursor or Anysphere.

## What the Public Repo Includes

The public repository includes:

- the native iOS and iPadOS app source
- Cursor Cloud Agent client, models, providers, and tests
- release, contribution, security, support, and roadmap documentation
- a sanitized App Store Connect workflow example
- public design assets used by the app

The source tree is meant to be buildable and inspectable without private hosted infrastructure.

## What the Public Repo Does Not Include

The public repository does not include:

- private App Store Connect app IDs or TestFlight group IDs
- Apple API keys, signing certificates, provisioning profiles, archives, or IPAs
- private Cursor API keys
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

## Why the Repo Stays Generic

The public repo stays generic so users can inspect and run the iOS app without being silently tied to a private service.

That means:

- Cloud Agent requests remain direct from iOS.
- public source does not contain private hosted endpoints
- local release automation uses examples instead of live maintainer config
- contributors can audit what the app does with Cursor API keys

Official TestFlight or App Store releases may use private signing and release configuration, but those values must stay outside the public repository.

## What to Keep Private

Keep these out of Git:

- Cursor API keys
- Apple API keys and signing assets
- APNs keys and certificates
- `.asc/workflow.json`
- `.env` and `.npmrc`
- generated archives and IPAs

The short version: the public repo should be enough to build and inspect the app. Private release and account values stay private.
