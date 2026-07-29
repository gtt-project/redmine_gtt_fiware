# Release Verification

Manual-but-scripted checks to run before tagging a release, on top of the
automated test suite. Each layer catches what the previous one cannot; the
whole pass takes roughly half an hour. First run: 2026-07-28/29 for v3.0
(results recorded on [issue #16](https://github.com/gtt-project/redmine_gtt_fiware/issues/16)).

## Layer 0 — automated suite (CI)

Two workflows must be green on the release commit:

- the Ruby matrix (Redmine/RedMica 6.0–7.0 x Ruby 3.3–4.0), covering models,
  controllers, builders, the REST API and the form's DOM contract;
- the JavaScript suite (`npm ci && npm test`, Vitest + jsdom), covering the
  subscription form's behaviour: row pickers, serialization, the JSON-mode
  toggle, the standard-aware toggles, the tracker-driven issue details and the
  guided flow.

Together they exercise no **real browser** and no **real broker** — that is
what the layers below are for.

## Layer 1 — auth mode drill (fake broker)

Verifies the three connection auth modes end to end through the real UI,
including the browser-mode JavaScript and CORS. Uses
[`scripts/fake_broker.py`](scripts/fake_broker.py), a dependency-free
header-echo broker: it logs every request as a JSON line, answers subscription
POSTs with `201` + `Location`, and speaks CORS.

1. Start it on the same container network as Redmine, with the port also
   published to the host (browser mode calls it from your browser):

   ```bash
   podman run -d --name fakebroker --network <redmine-network> -p 9999:9999 \
     -v $(pwd)/plugins/redmine_gtt_fiware/doc/scripts/fake_broker.py:/srv/broker.py:ro \
     docker.io/library/python:3-alpine python /srv/broker.py
   ```

   > Hostname rule: brokers reject URL hosts containing underscores
   > (`400 invalid custom /url/` from Orion), so reach Redmine and the fake
   > broker via underscore-free network aliases.

2. Seed one connection + template per mode (idempotent):

   ```bash
   VERIFY_PROJECT=<project-identifier> bundle exec rails runner \
     plugins/redmine_gtt_fiware/doc/scripts/seed_verification.rb
   ```

3. Open the project's FIWARE settings tab and drill each template. For the
   relayed and browser templates, first type any token (e.g. `relay-me-123`)
   into the token box; the stored template publishes with its stored token
   directly.

4. Compare `podman logs fakebroker` against this table — the **user-agent and
   origin tell you which side made the call**, which is the whole point:

   | Action | Expected request at the broker |
   | --- | --- |
   | stored publish | `POST` with `Authorization: Bearer stored-secret-789`, Ruby user-agent, no Origin |
   | relayed publish | `POST` with `Authorization: Bearer <typed token>`, Ruby user-agent (server relays; token not stored) |
   | browser publish | `OPTIONS` preflight, then `POST` **from the browser** (browser user-agent + `Origin` header) with `X-Api-Key: <typed token>` — the custom token header (#99) |
   | each unpublish | matching `DELETE` with the same auth header from the same side |

   Also check in Redmine: each publish stores a `fake-sub-N` subscription id
   (browser mode reports it back through a PATCH), each unpublish clears it to
   blank, and the page never displays a stored token.

## Layer 2 — real broker round trip (NGSIv2, local Orion)

Verifies the actual subscription payloads, `q` filter enforcement, notification
delivery, webhook authentication and issue creation against a real broker.

```bash
podman run -d --name orion-mongo --network <redmine-network> docker.io/library/mongo:5.0
podman run -d --name orion-v2 --network <redmine-network> -p 1026:1026 \
  docker.io/fiware/orion:3.12.0 -dbURI mongodb://orion-mongo
```

1. Create an NGSIv2 connection to `http://orion-v2:1026` (stored mode, no
   token — an open broker also verifies the token-less stored path).
2. Create a template with a query filter (e.g. `severity>3`) and geometry
   "Entity location", then publish it. The notification callback URL must be
   reachable **from the Orion container** (see #101: the URL is built from the
   publishing request's host, so publish from a host/alias Orion can resolve).
3. Three-phase filter test — create an entity below the threshold, update it
   to the boundary, then past it:

   ```bash
   curl -s http://localhost:1026/v2/entities -H 'Content-Type: application/json' -d \
     '{"id":"urn:verify:1","type":"<entity type>","severity":{"type":"Number","value":2},
       "location":{"type":"geo:json","value":{"type":"Point","coordinates":[139.69,35.69]}}}'
   curl -s http://localhost:1026/v2/entities/urn:verify:1/attrs -X PATCH \
     -H 'Content-Type: application/json' -d '{"severity":{"type":"Number","value":5}}'
   ```

   Expected: **no issue** for the below-threshold phases, **exactly one issue**
   after crossing it — with the subject/description rendered, the author set to
   the template's member, and the point geometry on the map. `GET
   /v2/subscriptions` shows `timesSent: 1`.
4. Exercise the Synchronize and Unpublish buttons; after unpublish the broker's
   subscription list is empty and the local subscription id is cleared.

## Layer 3 — NGSI-LD round trip (real LD broker)

Same shape as layer 2 against an NGSI-LD broker (hosted or local). Watch for:

- `NGSILD-Tenant` header (no service path in LD), `application/ld+json`,
  `@context` in the payload
- `notification.endpoint.receiverInfo` **must** arrive as real HTTP headers —
  the webhook-secret authentication depends on it
- notifications may carry `String`/`Number` attribute types and `Relationship`
  values under `value` instead of `object`; issues must still render
- broker callbacks need a publicly reachable Redmine URL (a
  `cloudflared tunnel --url http://127.0.0.1:3000` quick tunnel works; Rails
  host authorization must allow the tunnel host in development)
- **known upstream gap:** some brokers accept `q`/`geoQ` on subscriptions but
  do not apply them to notifications — run the layer 2 three-phase test here
  too and record the result

## Cleanup

```bash
podman rm -f fakebroker orion-v2 orion-mongo
```

Delete the `Verification broker (...)` connections and `Verification: ... mode`
templates from the UI (or rerun the seeder next time — it is idempotent).

## Future automation

The form's client-side logic is covered by the Vitest suite in layer 0 since
version 3.2. The remaining promotion path is browser-driven system tests
(Capybara/headless Chrome, as Redmine core uses) for layer 1, and a scripted
layer 2 harness.
