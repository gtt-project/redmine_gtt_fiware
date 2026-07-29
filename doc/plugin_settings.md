# Plugin Settings

Administration → Plugins → Redmine GTT FIWARE plugin → Configure.

Broker URLs, authentication and throttling are not configured here: they live
on [FIWARE Connections](broker_connections.md) since version 3.0.

## Issue Emission

- **Instance identifier**: letters, digits, hyphen and underscore. It becomes
  part of every emitted entity id
  (`urn:ngsi-ld:Issue:redmine:<instance>:<issue>`), so other organizations can
  tell your work orders apart from theirs. [Issue emission](issue_emission.md)
  stays off while this is blank. Choose it once and keep it: changing it later
  re-identifies every emitted entity.

## Notification Attachment Downloads

Attachments referenced in broker notifications are downloaded over HTTPS only,
from an allowlist of hosts.

- **Additional allowed hosts**: one host per line. The subscription's
  broker host is always allowed.
- **Allowed content types**: one content type per line; wildcards like
  `image/*` are supported. Leave blank for the default list (common image
  formats, PDF, plain text, CSV, JSON).
