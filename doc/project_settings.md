# Project Settings

## Modules

The plugin provides two project modules (project → Settings → Modules):

- **GTT FIWARE**: enables the FIWARE tab and subscriptions for the project.
- **GTT FIWARE Issue Emission**: opts the project's issues into
  [issue emission](issue_emission.md). This is a separate module on purpose:
  publishing issue data to a broker is an explicit decision, never a side
  effect of using subscriptions.

## The FIWARE tab

With the GTT FIWARE module enabled, a **FIWARE** tab appears in the project
settings. It lists the project's subscriptions and offers:

- **New Subscription**: opens the
  [subscription form](subscription_template.md).
- For each subscription:
  - **Clipboard**: copies a cURL command that registers the subscription on
    the broker. Useful when the broker is not reachable from the Redmine
    server (a stored token is replaced by a `<token>` placeholder).
  - **Publish / Unpublish**: register or remove the subscription on the
    broker. For connections with a stored token this runs on the server; for
    relayed and browser connections, a token box above the list takes the
    token for the request.
  - **Synchronize**: fetches the subscription's state from the broker and
    updates the local status (for example when it was removed or expired on
    the broker side).
  - **Delete**: removes the subscription in Redmine.

The table shows each subscription's connection details (NGSI standard, broker
URL), the issue defaults (status, tracker) and the subscription status
(active, inactive, oneshot).
