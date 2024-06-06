# Project Settings

## Enabling the Plugin for a Project

To use the plugin, it needs to be enabled for each project. Once enabled, a
**FIWARE** tab will appear in the project settings.

1. Go to the project where you want to enable the plugin.
2. Navigate to **Settings**.
3. Click on the **Modules** tab.
4. Check the **GTT FIWARE** module to enable it.
5. Click **Save**.

## FIWARE Tab in Project Settings

After enabling the plugin for the project, the **FIWARE** tab will appear in the
project settings. This tab allows you to create and manage subscription templates.

![Project Settings - FIWARE Tab](project_settings.png)

- **Authorization token**: Bearer token to be included in the request headers.
  Leave empty for no authorization. The token is not stored in the database.
  When the PROXY button is enabled (green), the request will be proxied through
  the server.

### Creating a New Subscription Template

In the **FIWARE** tab, you can create a new subscription template by clicking on
the **New Subscription Template** button. This will open a form where you can
configure the template settings, see:

- [Subscription Templates](subscription_template.md)

### Managing Subscription Templates

In the **FIWARE** tab, you can view, edit, and delete existing subscription
templates. You can also copy the template settings cURL command to the clipboard.
This can be useful if the context broker is not accessible from the Redmine server.

In case the context broker is accessible from the Redmine server, you can also
(un)publish a template directly if needed.

### Subscription Templates Table

The subscription templates table displays the existing templates with their key details:

- **Name**: The name of the subscription template. By clicking on the name, you
  can view and edit the template settings.
- **NGSI standard**: The NGSI standard used (e.g., *NGSIv2*).
- **Broker URL**: The URL of the FIWARE context broker.
- **Issue status**: The status of the Redmine issue that will be created.
- **Tracker**: The tracker to be used for the Redmine issue.
- **Status**: The status of the subscription template (e.g., active, inactive, oneshot).

#### Actions

For each subscription template, you have the following actions available:

- **Clipboard**: Copy the template settings to the clipboard. In case the
  browser does not support clipboard copying, the cURL command will be also
  displayed in the developer console.
- **Publish**: Publish the subscription template to the context broker.
- **Unpublish**: Unpublish the subscription template (if it is currently published).
- **Delete**: Delete the subscription template.

These settings allow you to customize how FIWARE notifications are handled and
how Redmine issues are created or updated based on these notifications.
