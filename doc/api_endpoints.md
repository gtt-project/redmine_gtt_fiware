# API Endpoints

## "Context" API endpoints

| Context          | URL                                                       |
|------------------|-----------------------------------------------------------|
| General Redmine  | `http://localhost:3000/ngsi/data-models/redmine-context.jsonld` |
| GTT Redmine      | `http://localhost:3000/ngsi/data-models/redmine-gtt-context.jsonld` |
| Issues           | `http://localhost:3000/ngsi/data-models/redmine-issues-context.jsonld` |
| Projects         | `http://localhost:3000/ngsi/data-models/redmine-projects-context.jsonld` |
| Users            | `http://localhost:3000/ngsi/data-models/redmine-users-context.jsonld` |
| Versions         | `http://localhost:3000/ngsi/data-models/redmine-versions-context.jsonld` |
| Categories       | `http://localhost:3000/ngsi/data-models/redmine-categories-context.jsonld` |
| Trackers         | `http://localhost:3000/ngsi/data-models/redmine-trackers-context.jsonld` |
| Statuses         | `http://localhost:3000/ngsi/data-models/redmine-statuses.jsonld` |
| Priorities       | `http://localhost:3000/ngsi/data-models/redmine-priorities-context.jsonld` |
| Attachments      | `http://localhost:3000/ngsi/data-models/redmine-attachments-context.jsonld` |
| Relations        | `http://localhost:3000/ngsi/data-models/redmine-relations-context.jsonld` |
| Journals         | `http://localhost:3000/ngsi/data-models/redmine-journals-context.jsonld` |
| Details          | `http://localhost:3000/ngsi/data-models/redmine-details-context.jsonld` |

## NGSI-LD and NGSIv2 API endpoints

- `.json` returns NGSIv2
- `.jsonld` returns NGSI-LD (The Optional query parameter `?normalized=true|false`
  can be set to switch between normalized and not-normalized format for NGSI-LD.)

| Entity     | NGSI-LD/NGSIv2                                                  |
|------------|-----------------------------------------------------------------|
| Issue      | GET `http://localhost:3000/ngsi/issues/{id}.{jsonld,json}`      |
| Project    | GET `http://localhost:3000/ngsi/projects/{id}.{jsonld,json}`    |
| User       | GET `http://localhost:3000/ngsi/users/{id}.{jsonld,json}`       |
| Version    | GET `http://localhost:3000/ngsi/versions/{id}.{jsonld,json}`    |
| Category   | GET `http://localhost:3000/ngsi/categories/{id}.{jsonld,json}`  |
| Tracker    | GET `http://localhost:3000/ngsi/trackers/{id}.{jsonld,json}`    |
| Status     | GET `http://localhost:3000/ngsi/statuses/{id}.{jsonld,json}`    |
| Priority   | GET `http://localhost:3000/ngsi/priorities/{id}.{jsonld,json}`  |
| Attachment | GET `http://localhost:3000/ngsi/attachments/{id}.{jsonld,json}` |
| Relation   | GET `http://localhost:3000/ngsi/relations/{id}.{jsonld,json}`   |
| Journal    | GET `http://localhost:3000/ngsi/journals/{id}.{jsonld,json}`    |
| Detail     | GET `http://localhost:3000/ngsi/details/{id}.{jsonld,json}`     |
