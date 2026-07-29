# FIWARE Connections

Administration → FIWARE Connections.

A connection describes one context broker: URL, NGSI standard, tenant,
authentication. Subscription templates and issue emission both use
connections, so broker details are entered once and reused.

## Fields

- **Name**: how the connection appears in template forms.
- **NGSI standard**: `NGSIv2` or `NGSI-LD`. The template form adapts to the
  selected standard (for example, `@context` only applies to NGSI-LD,
  `Fiware-ServicePath` only to NGSIv2).
- **Broker URL**: the broker's base URL. A URL that already contains a
  versioned API path (for example `.../ngsi-ld/v1`) is used as is; otherwise
  the standard's default prefix is appended.
- **FIWARE Service**: the tenant name. Sent as `Fiware-Service` (NGSIv2) or
  `NGSILD-Tenant` (NGSI-LD).
- **FIWARE Service Path**: NGSIv2 only.
- **NGSI-LD Context**: the default `@context` for subscriptions on this
  connection; a template can override it.
- **Authentication**: where the broker token comes from.
  - *Stored*: the token is saved encrypted in the database and the server
    calls the broker. Required for issue emission and federation queries,
    which run server-side.
  - *Relayed*: the token is typed in the browser on every publish and the
    server makes the call. Nothing is stored.
  - *Browser*: the browser calls the broker directly (the broker must be
    reachable from the browser and allow CORS).
- **Token header**: blank sends `Authorization: Bearer <token>`. Any other
  header name (for example `X-Api-Key`) sends the token as is, which is what
  API-key gateways expect.
- **Throttling (s)**: minimum seconds between notifications for this
  connection's subscriptions. A template can override it.

## Issue Emission section

For NGSI-LD connections, the form also lists the trackers with a checkbox and
a subtype per tracker. This controls which issues are published to this broker
and how; see [Issue emission](issue_emission.md).
