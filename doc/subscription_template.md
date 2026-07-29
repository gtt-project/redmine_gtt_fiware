# Subscriptions

A subscription tells a context broker which entity changes to send to Redmine,
and how to turn each notification into an issue. Subscriptions are managed per
project: Settings → FIWARE → **New Subscription**.

The form shows the essential fields first; everything else lives in three
collapsible sections. A new subscription is publishable with just the visible
fields.

## Basics

- **Name** (required).
- **FIWARE connection** (required): the broker to subscribe on; see
  [FIWARE Connections](broker_connections.md). The form adapts to the
  connection's NGSI standard, and fields that do not apply are hidden.
- **Entities**: which entity types (and optionally id patterns or exact ids)
  the subscription covers. The rows can also be edited as raw JSON.
- **Tracker** and **Subject** (required): the issue defaults. Attribute
  readings can be embedded anywhere in the issue texts as `${...}`
  placeholders, for example `${id}`, `${type}`, `${temperature}` or
  `${attrs.temperature.value}`.
- **Preview with a sample entity**: renders the subject and description
  against a real entity fetched from the broker, before anything is saved or
  published.

## Filters

- **Watched attributes**: notify only when one of these attributes changes.
- **Query**: an attribute condition, for example `severity>3`.
- **Area**: no geographic filter, the project boundary, or a custom
  georel/geometry/coordinates triple.
- **Alteration types** and **Notify on metadata change**: which kinds of
  entity changes notify (the options follow the connection's NGSI standard).

## Issue details

- **Description** and **Issue notes** templates (`${...}` placeholders work
  here too). The notes template is used when a notification updates an
  existing issue instead of creating a new one.
- **Threshold (h)**: within this window, repeated notifications for the same
  entity update the first issue (adding the notes) instead of creating
  duplicates. `0` creates a new issue every time.
- **Issue geometry**: the entity's location, a custom GeoJSON template, or
  none.
- **Attachments**: URLs (with `${...}` placeholders) downloaded and attached
  to the issue; see the allowlist in the
  [plugin settings](plugin_settings.md).
- **Issue status, priority, category, version**: the created issue's fields.
- **Sent from user** (required): the member the issues are authored as. Use a
  dedicated user with just the needed permissions, not an administrator.

## Subscription options

- **Subscription status**: active, inactive or oneshot (oneshot is NGSIv2
  only).
- **Expiration date**.
- **NGSI-LD Context**: overrides the connection's default `@context`.
- **Federation** and **Federation watch**: see [Federation](federation.md).
- **Throttling (s)**: overrides the connection's throttling.
- **Subscription ID**: set automatically when publishing; shown for
  reference.

## Publishing

Publish from the FIWARE tab (or directly with **Create and publish** for
connections with a stored token). The broker then confirms the subscription
and its id is stored. **Synchronize** re-reads the subscription's state from
the broker; **Unpublish** removes it.

The notification endpoint that receives the broker's callbacks is
authenticated by a per-subscription secret, generated automatically and
included when publishing. Callback URLs are built from
**Administration → Settings → Host name**, so make sure it is set to a host
the broker can reach.
