# Adaptive Service Endpoints Design

**Date:** 2026-08-20

**Status:** Approved

**Projects:**

- Flutter client: `/Volumes/ext/MusicFree/flutter-client`
- TuneFlow Service: `/Volumes/ext/lx-music-server-web`

## Goal

Allow the Flutter client to keep a stable logical connection to one TuneFlow
Service while automatically choosing its configured LAN or external origin as
the device moves between Wi-Fi, Ethernet, mobile, VPN, and offline networks.
The first address entered by the user remains a durable bootstrap fallback.

## Non-goals

- Discovering the NAS host address from inside a Docker bridge network.
- Scanning the local subnet or using mDNS to discover unknown servers.
- Retrying arbitrary API mutations across origins.
- Restarting an already-playing audio stream solely because the preferred
  Service origin changed.
- Adding server identity, authentication, or certificate-pinning protocols.

## Service settings and health contract

The Service owns two new persisted settings:

```text
service.lanOrigin
service.externalOrigin
```

Both default to the empty string. The existing Service network-settings UI
adds labeled inputs for the LAN access address and external access address.
Each non-empty value must be a complete HTTP(S) origin such as
`http://192.168.1.20:3124` or `https://music.example.com`.

The Service normalizes accepted values by removing a trailing root slash. It
rejects unsupported schemes, missing hosts, credentials, non-root paths,
queries, and fragments. An empty string clears a configured address. Invalid
patches do not change persisted settings.

`GET /api/v1/health` returns the configured values without attempting to infer
the Docker host address:

```json
{
  "data": {
    "status": "ok",
    "lanOrigin": "http://192.168.1.20:3124",
    "externalOrigin": "https://music.example.com"
  }
}
```

An unconfigured address is returned as `""`. The OpenAPI response schema is
updated accordingly. Existing Docker and deployment health checks continue to
use only the HTTP success status and `status` value.

## Client persisted endpoint state

The client stores four independent normalized origins:

| Value | Purpose | Updated by |
| --- | --- | --- |
| `bootstrapOrigin` | First or most recent address manually confirmed by the user; permanent fallback | Successful manual connection only |
| `lastConnectedOrigin` | Last origin successfully committed as the active API origin | Successful manual or automatic selection |
| `lanOrigin` | Most recent valid LAN origin advertised by `/health` | Successful health responses |
| `externalOrigin` | Most recent valid external origin advertised by `/health` | Successful health responses |

The existing `service_origin` preference migrates to `bootstrapOrigin`. If
`lastConnectedOrigin` is absent during migration, the same legacy value seeds
it. The migration is idempotent and preserves all unrelated UI preferences.

A successful health response may update either discovered value without
overwriting `bootstrapOrigin`. During a manual connection flow, discovered
values remain staged in memory until one candidate completes health and API v1
validation; if the flow ultimately fails, none of the four persisted values
changes. An explicit user disconnect clears all four endpoint values.

## Candidate priority and selection

The client treats Wi-Fi and Ethernet as LAN-capable. Mobile, VPN-only, and
other available transports use the external route. When connectivity reports
no transport, the client does not probe and waits for a later network event.
Actual reachability is always established by an HTTP health probe; transport
type alone never marks an endpoint reachable.

Candidate order is:

- Wi-Fi or Ethernet: `lanOrigin`, `externalOrigin`, `bootstrapOrigin`.
- Other available transport: `externalOrigin`, `bootstrapOrigin`.

Candidates are normalized and de-duplicated. An origin returned by a successful
health response is persisted and inserted into the current selection queue at
its semantic priority. Therefore an external or bootstrap probe that discovers
a new LAN origin on Wi-Fi causes that LAN origin to be probed before the
external origin is committed. Already visited origins are never revisited in
the same selection run, and the dynamic candidate set has a fixed upper bound
of eight origins.

Cold start is optimized separately:

1. Probe `lastConnectedOrigin` first when it exists.
2. If it succeeds and supports API v1, restore the stable session immediately.
3. Refresh discovered origins from that response.
4. Re-evaluate the preferred candidates in the background using the current
   network type.
5. If the last origin fails, run the normal priority list before showing the
   existing connection-failure route.

The first successful health response is retained as a fallback while any newly
discovered higher-priority candidate is evaluated. Before an origin is
committed, `GET /api/v1/capabilities` must succeed and report `apiVersion` equal
to `v1`. Failure of the capability check rejects that candidate and advances
to the next candidate.

Older Services remain compatible. A response with `status == "ok"` and no
origin fields is healthy; missing, empty, or syntactically invalid advertised
origins are ignored.

## Probe utility

`ServerEndpointProbe` is a standalone, dependency-injected utility. It owns
health-request retry behavior and health-payload parsing but does not mutate
application state or the active API origin.

For each candidate it performs at most three total health attempts:

- each attempt has a three-second timeout;
- after the first or second failure it waits two seconds;
- it does not wait after the third failure;
- it stops immediately after the first valid `status == "ok"` response.

The request function and delay function are injectable so timing and retry
behavior can be tested without real sleeps. A successful result contains the
probed origin, normalized advertised origins, and measured latency. Network,
timeout, non-success HTTP, malformed JSON envelope, and unhealthy-status errors
are represented as failed probe attempts.

## Network and lifecycle coordination

`NetworkTypeMonitor` wraps `connectivity_plus`. It exposes the current set of
transports and a stream of changes through an application-owned interface so
tests do not depend on platform method channels.

The connection coordinator:

- checks the initial transport after restoring preferences;
- listens for Wi-Fi changes, Ethernet changes, and transport changes;
- de-duplicates equivalent transport sets and briefly debounces event bursts;
- requests a new selection when the App returns to the foreground;
- tags each selection with an increasing generation number;
- prevents a stale generation from committing after a newer event;
- asks an obsolete probe to stop at its next request or retry boundary.

At most an already-running three-second HTTP attempt can overlap a newer
generation. Its result is discarded. No API mutation is automatically retried
as part of endpoint selection.

## Stable session and base-origin switching

Automatic selection must not replace the logical connected Service session.
`ServiceApi` therefore owns a mutable active origin that is changed only after
health and capability validation. Existing repositories keep the same API
object and automatically resolve subsequent requests against the new origin.

The player provider must depend on stable session identity rather than the
active-origin value. Automatic origin changes consequently preserve the queue,
current track, playback position, and the already-open audio stream. Subsequent
playback resolution, artwork, lyrics, downloads, and ordinary API requests use
the new origin. SSE reconnects against the new origin after the transport is
re-established.

Manual connection to a different Service creates a new session and closes the
old API client, retaining the existing behavior for an intentional server
change.

Committing an automatic switch consists of updating the active API origin and
persisting `lastConnectedOrigin`. If persistence fails after the network switch,
the verified live origin remains active and the error is recorded for
diagnostics; the client does not revert to a known-unreachable origin.

If every candidate fails during an automatic re-evaluation, the current session
and UI remain intact and diagnostics record that the endpoint is temporarily
unreachable. If every candidate fails during cold start, the existing
connection-failure screen is shown with the bootstrap address available for
editing.

## User-visible diagnostics

The Flutter settings diagnostics show the actual active origin, detected
transport class, most recent check time, latency, and either connected or
temporarily unreachable status. Successful automatic switches are silent to
avoid noisy notifications during Wi-Fi transitions. Manual validation failures
continue to use the existing actionable connection-error presentation.

The Service network-settings UI uses the existing input and settings-update
patterns, with Simplified Chinese, Traditional Chinese, and English labels and
descriptions for both origins.

## Platform behavior

Android keeps its existing cleartext HTTP allowance for private LAN origins.
iOS and macOS receive the platform declarations needed to explain or permit
local-network access without disabling TLS validation globally. HTTPS
certificate errors remain real probe failures; the client never bypasses
certificate verification.

## Verification

Service coverage verifies:

- empty defaults for both settings;
- accepted normalization and rejected invalid origins;
- persistence across restart;
- settings UI fields and translations;
- `/health` response values and OpenAPI schema;
- unchanged Docker health behavior.

Flutter coverage verifies:

- legacy preference migration and independent persistence of all endpoint
  values;
- three attempts, three-second timeout, two-second inter-attempt delay, and
  early success in `ServerEndpointProbe`;
- health parsing, normalization, invalid-value handling, and old-Service
  compatibility;
- LAN-capable and external candidate ordering, de-duplication, dynamic
  discovery, and the candidate bound;
- cold-start restoration, automatic re-evaluation, and all-candidates-failed
  behavior;
- transport-event de-duplication and stale-generation suppression;
- stable player/session identity while subsequent API requests use the new
  origin;
- manual server replacement and explicit disconnect behavior;
- settings diagnostics for active and temporarily unreachable states.

Implementation uses test-first red-green-refactor cycles. Final verification
runs the focused Service tests and type checks, focused Flutter unit/widget
tests and static analysis, then reviews both repository diffs to ensure the
pre-existing dirty-worktree changes were preserved.
