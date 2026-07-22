# Redmine NGSI-LD vocabulary (reference)

**Status:** reference material, not an active code path.

This document preserves the JSON-LD vocabulary that the plugin's original
`ngsi/*` read API exposed, before that API was removed (see issue #60). No
context broker could consume that API (the paths were not NGSI-LD API paths and
there were no query semantics), so the controllers, presenters, `@context`
endpoint and views were deleted. The *vocabulary* they encoded is kept here
because it is the seed for the entity model the plugin will **emit** to a broker
in Phase 3 (#69).

The exact original implementation (14 `ngsi/*` controllers, 14 presenters, 14
`@context` templates, and the `JsonldHelper` / `CustomFieldHelper` helpers) is
preserved in git history in the commit immediately before this file was added.
Retrieve it with, e.g.:

```bash
git log --oneline -- app/controllers/ngsi
git show <commit>:app/presenters/issue_presenter.rb
```

Everything below is descriptive, not normative: Phase 3 is free to correct the
known problems noted inline (mis-pointed `@id`s, missing types) rather than copy
them.

## Namespaces and base context

Every entity context imported the NGSI-LD core context plus this base
(`redmine` context):

| Prefix | IRI |
| --- | --- |
| (core) | `https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld` |
| `xsd` | `http://www.w3.org/2001/XMLSchema#` |
| `geo` | `https://uri.etsi.org/ngsi-ld/geo/` |
| `redmine` | `<base_url>/ngsi/data-models/redmine/` |

Entity type terms defined in the base context: `Attachment`, `Category`,
`Journal`, `Priority`, `Project`, `Relation`, `Status`, `Tracker`, `User`,
`Version` (each `redmine:<Type>`). Common temporal terms: `createdAt`,
`modifiedAt` (both `xsd:dateTime`).

For Phase 3 the `redmine:` namespace should become a stable, published
`@context` URL with instance-scoped entity URNs
(`urn:ngsi-ld:...:redmine:<instance-id>:<issue-id>`), rather than a per-request
`base_url`-derived namespace.

## Representations

`BasePresenter#render_ngsi` produced three shapes from the same normalized
source, driven by the `normalized` and `ngsiv2` flags (the plugin setting
`ngsi_ld_format` selected the default):

- **Normalized NGSI-LD** — full `{ "type": "Property"|"Relationship"|"GeoProperty", ... }` objects.
- **Key-values (non-normalized) NGSI-LD** — `JsonldHelper.to_non_normalized`
  collapses each attribute to its bare value: a `Property` becomes its
  `value` (unwrapping `{@type,@value}` typed values), a `Relationship` becomes
  its `object`, a `GeoProperty` becomes its GeoJSON `value`.
- **NGSIv2 fallback** — `JsonldHelper.to_ngsi_v2` further drops `@context`,
  rewrites `.jsonld` links to `.json`, strips the `?normalized=` query, and
  remaps `GeoProperty` → `{ "type": "geo:json", "value": ... }`.

Phase 3 should keep NGSI-LD normalized as the first-class form with an optional
key-values projection, and treat NGSIv2 as a compatibility fallback only.

## GTT geo terms (`gtt` context)

The GTT-specific terms are the reason a bespoke vocabulary exists at all — they
carry the geometry that Smart Data Models do not model for Redmine work items:

| Term | `@id` | Type | Source |
| --- | --- | --- | --- |
| `location` | `redmine:location` | `geo:GeoProperty` | issue `geom` → `geojson['geometry']` |
| `rotation` | `redmine:rotation` | `xsd:decimal` | (GTT rotation attribute) |

`location` maps a GTT 3D point/line/polygon geometry directly to an NGSI-LD
`GeoProperty` whose value is GeoJSON. This is the core of the Phase 3 emit model.

## Issue entity (primary Phase 3 emit target)

`type: "Issue"`. Terms, their NGSI-LD kind, and the Redmine source
(`IssuePresenter`). Relationship objects pointed at the corresponding entity's
`show` URL; in Phase 3 they become entity URNs.

| Term | Kind | Redmine source | Notes |
| --- | --- | --- | --- |
| `subject` | Property (`xsd:string`) | `issue.subject` | |
| `description` | Property (`xsd:string`) | `issue.description` | gated on `disabled_core_fields` |
| `isPrivate` | Property (`xsd:boolean`) | `issue.is_private` | |
| `createdAt` | Property (`xsd:dateTime`) | `issue.created_on` | |
| `modifiedAt` | Property (`xsd:dateTime`) | `issue.updated_on` | |
| `startDate` | Property (`xsd:dateTime`) | `issue.start_date` | gated |
| `dueDate` | Property (`xsd:dateTime`) | `issue.due_date` | gated |
| `closedDate` | Property (`xsd:dateTime`) | `issue.closed_on` | `null` when open |
| `doneRatio` | Property (`xsd:decimal`) | `issue.done_ratio` | gated |
| `estimatedHours` / `totalEstimatedHours` | Property (`xsd:decimal`) | `issue.estimated_hours` / `total_estimated_hours` | gated |
| `spentHours` / `totalSpentHours` | Property (`xsd:decimal`) | `issue.spent_hours` / `total_spent_hours` | only if `view_time_entries` |
| `location` | GeoProperty | `issue.geom` → GeoJSON | `null` when no geometry |
| `hasProject` | Relationship | `project_id` | |
| `hasTracker` | Relationship | `tracker_id` | |
| `hasStatus` | Relationship | `status_id` | |
| `hasPriority` | Relationship | `priority_id` | |
| `hasAuthor` | Relationship | `author_id` | |
| `hasAssignee` | Relationship | `assigned_to_id` | gated |
| `hasCategory` | Relationship | `category_id` | gated |
| `hasVersion` | Relationship | `fixed_version_id` | gated |
| `hasParent` | Relationship | `parent_id` | gated |
| `hasChildren` | Relationship set | `children` | |
| `hasRelations` | Relationship set | `relations` | |
| `hasJournals` | Relationship set | `journals` | |
| `hasAttachments` | Relationship set | `attachments` | |
| `hasWatchers` | Relationship set | `watcher_users` | |
| `allowedStatuses` | Relationship set | `new_statuses_allowed_to(User.current)` | permission-derived |
| `cf<Name>` | Property/Relationship | visible custom field values | see custom fields below |

The `issues` context also declares (commented out in the original)
`hasChangesets` — left for Phase 3 if repository linkage is wanted.

## Supporting entities

These entities existed to make the Issue graph navigable. Phase 3 likely
inlines or references a subset rather than emitting them all. Terms per their
`@context` templates:

- **Project**: `name`, `identifier`, `description`, `homepage` (`xsd:string`);
  `status`, `isPublic` (`xsd:integer`); `createdOn`, `updatedOn`
  (`xsd:dateTime`); `hasParentProject` (Rel); `hasMembers`, `hasTrackers`,
  `hasCategories` (Rel sets). Also imports the `gtt` context (project boundary
  geometry). Commented-out: `hasModules`, `hasActivities`, `hasCustomFields`.
- **Tracker**: `name`, `description` (`xsd:string`); `standardFields`
  (`xsd:string` set); `defaultStatus` (Rel).
- **Status**: `name` (`xsd:string`); `isClosed` (`xsd:boolean`). TODO in
  original: `position`, `default_done_ratio`.
- **Priority**: `name` (`xsd:string`); `isDefault`, `active` (`xsd:boolean`).
- **User**: `login`, `firstName`, `lastName`, `email` (`xsd:string`); `status`
  (`xsd:integer`); `lastLoginDate` (`xsd:dateTime`). Imports the `gtt` context.
- **Version**: `name`, `description`, `sharing` (`xsd:string`); `status`
  (`xsd:integer`); `dueDate` (`xsd:dateTime`); `estimatedHours`, `spentHours`
  (`xsd:decimal`); `hasProject` (Rel). Drops `hasWikiPage`.
- **Category**: `name` (`xsd:string`); `hasProject`, `hasAssignee` (Rel).
- **Journal**: `notes`, `privateNotes`; `hasIssue`, `hasAuthor` (Rel);
  `hasDetails` (Rel set). Note: in the original, `notes`/`privateNotes` `@id`s
  were mis-pointed (`redmine:delay` / `redmine:Issue`) — fix in Phase 3.
- **Detail** (journal detail): `property`, `propKey`, `oldValue`, `value`
  (`xsd:string`); `hasJournal` (Rel).
- **Relation**: `relationType` (`xsd:string`); `delay` (`xsd:decimal`);
  `fromIssue`, `toIssue` (Rel).
- **Attachment**: `filename`, `contentType`, `description` (`xsd:string`);
  `filesize` (`xsd:integer`); `contentUrl`, `thumbnailUrl`; `hasAuthor` (Rel).

## Custom fields

`CustomFieldHelper` mapped each visible custom field to a term named
`cf<CamelCaseName>` (from the field's display name), typed by Redmine
`field_format`:

| `field_format` | NGSI-LD kind | value |
| --- | --- | --- |
| `string`, `text` | Property | string |
| `int` | Property | integer |
| `float` | Property | decimal |
| `bool` | Property | boolean (`1`/`0` → `true`/`false`, else `null`) |
| `date` | Property | typed value `{@type: Date, @value}` |
| `list`, `enumeration` | Property | string or array (empty → `null`) |
| `version`, `link`, `attachment` | Property | string (empty → `null`) |
| `user` | Relationship | user entity reference |

Note: the original `user` custom-field branch had an inverted `present?` guard
(it emitted `null` when a value was present) — fix in Phase 3.
