# REST API

Since version 3.2 subscriptions can be read and written over Redmine's REST
API, in JSON and XML. Enable **Administration → Settings → API → Enable REST
web service** first, and authenticate as usual: an `X-Redmine-API-Key` header,
`key=` parameter, or HTTP Basic. The acting user needs the *Manage
Subscriptions* permission in the project, and the project needs the GTT FIWARE
module.

FIWARE connections are not part of the API: they hold broker credentials and
stay an administration surface.

## Endpoints

All endpoints live under a project.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/projects/:project_id/subscription_templates.json` | list the project's subscriptions |
| GET | `/projects/:project_id/subscription_templates/:id.json` | one subscription |
| POST | `/projects/:project_id/subscription_templates.json` | create one |
| PUT | `/projects/:project_id/subscription_templates/:id.json` | update one |
| DELETE | `/projects/:project_id/subscription_templates/:id.json` | delete one |

The list is paginated with the usual `offset` and `limit` parameters and
reports `total_count`. Replace `.json` with `.xml` for XML.

Publishing to the broker is not part of the API: it belongs to the
[project's FIWARE tab](project_settings.md), which also relays a browser token
when the connection needs one. `subscription_id` and `published` tell you
whether a subscription is currently registered on a broker.

## What a subscription looks like

```bash
curl -H "X-Redmine-API-Key: $KEY" \
  https://redmine.example.org/projects/city-parks/subscription_templates.json
```

```json
{
  "subscription_templates": [
    {
      "id": 1,
      "name": "Waste containers",
      "status": "active",
      "subscription_id": "urn:ngsi-ld:Subscription:6f1c",
      "published": true,
      "project": { "id": 1, "name": "City Parks" },
      "broker_connection": { "id": 2, "name": "City broker", "standard": "NGSI-LD" },
      "entities": [{ "type": "WasteContainer", "idPattern": ".*" }],
      "attrs": ["fillingLevel"],
      "alteration_types": ["entityCreate", "entityChange"],
      "tracker": { "id": 4, "name": "Task" },
      "issue_status": { "id": 1, "name": "New" },
      "member": { "id": 1, "name": "Aiko Tanaka" },
      "subject": "Waste container needs emptying",
      "geometry": "${location}",
      "federation_policy": "annotate",
      "geofence_notes": false
    }
  ],
  "total_count": 1,
  "offset": 0,
  "limit": 25
}
```

Associations are rendered as `id`/`name` references and omitted when unset.
The per-subscription webhook secret is never returned: it authenticates broker
notifications and stays on the server. Neither is anything from the connection
beyond its identity, since that is where the stored broker token lives.

## Creating and updating

Send the fields under a `subscription_template` object. The required ones are
`broker_connection_id`, `name`, `subject`, `description`, the entity filter,
`tracker_id`, `issue_status_id` and `member_id`.

```bash
curl -X POST -H "X-Redmine-API-Key: $KEY" -H "Content-Type: application/json" \
  https://redmine.example.org/projects/city-parks/subscription_templates.json \
  -d '{
    "subscription_template": {
      "broker_connection_id": 2,
      "name": "Weather stations",
      "subject": "Reading from ${id}",
      "description": "Temperature is ${attrs.temperature.value}",
      "entities": [{ "type": "WeatherObserved", "idPattern": ".*" }],
      "attrs": ["temperature"],
      "tracker_id": 4,
      "issue_status_id": 1,
      "member_id": 1
    }
  }'
```

Structures go in as structures: `entities` and `attachments` as arrays of
objects, `attrs` as an array of names, `geometry` as GeoJSON (or the
`"${location}"` placeholder). The `*_string` variants the web form posts are
accepted too, for parity with it.

A create returns `201 Created` with the new subscription and a `Location`
header. Update and delete return `204 No Content`. Invalid input returns `422`
with an `errors` array, in Redmine's usual shape.

Omitted fields are left untouched on update, and on create take their
defaults, so `alteration_types` need not be sent to get the usual
create-and-change triggers.

## See also

- [Subscriptions](subscription_template.md) for what each field means
- [FIWARE Connections](broker_connections.md) for the broker side
