# Runline Notification Backend Contract

Status: app-side contract ready
Target app: iOS 26+

The iOS app now stores notification preferences, receives APNs device tokens, and supports deep links. A backend is still required to bridge Cursor events to APNs.

## Device Registration

`POST /v1/devices`

Request body:

```json
{
  "deviceID": "E7B6F7BC-5F72-49F3-8B36-6F08EED96D1D",
  "tokenHex": "apns-token-hex",
  "environment": "sandbox",
  "preferences": {
    "runStarted": true,
    "runFinished": true,
    "runFailed": true,
    "artifactReady": true,
    "pullRequestCreated": true
  },
  "appVersion": "0.1 (1)",
  "updatedAt": "2026-04-27T14:00:00Z"
}
```

`DELETE /v1/devices/{deviceID}`

Deletes the APNs token and all server-side notification preferences for that device.

## Cursor Event Intake

`POST /webhooks/cursor`

The backend should accept Cursor event/webhook payloads or a server-side polling job should normalize Cursor state into this event shape:

```json
{
  "event": "runFinished",
  "agentID": "agent_123",
  "runID": "run_123",
  "artifactPath": "artifacts/build.log",
  "pullRequestURL": "https://github.com/acme/app/pull/42"
}
```

Supported event values:

- `runStarted`
- `runFinished`
- `runFailed`
- `artifactReady`
- `pullRequestCreated`

## APNs Payload Rules

Push payloads must stay identifier-only by default:

```json
{
  "aps": {
    "alert": {
      "title": "Cursor run finished",
      "body": "Open Runline for details."
    },
    "sound": "default"
  },
  "event": "runFinished",
  "agentID": "agent_123",
  "runID": "run_123",
  "deepLinkURL": "runline://agents/agent_123/runs/run_123"
}
```

Do not include prompt text, transcript text, source code, diff contents, artifact contents, or Cursor API keys in APNs payloads.

## Backend Requirements

- Store APNs tokens encrypted at rest.
- Separate sandbox and production APNs credentials.
- Apply each device's `NotificationPreferences` before sending.
- Use `runline://agent/{agentID}` and `runline://agents/{agentID}/runs/{runID}` deep links.
- Treat Cursor API keys as backend secrets only when server-side polling is used.
- Add delivery retry/backoff and remove invalid APNs tokens after terminal APNs errors.
