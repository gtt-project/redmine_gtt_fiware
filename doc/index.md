# Redmine GTT FIWARE Plugin Documentation

This documentation provides detailed instructions on how to use the Redmine GTT
FIWARE plugin and its API endpoints.

## First Steps

- Make sure REST web services is enabled: <http://localhost:3000/settings?tab=api>
- Enable the plugin in project settings

To allow **public** access to NGSI-LD context documents, it's necessary to grant
*View* permissions to the *Anonymous* role.

![Plugin permissions](permissions.png)

## Table of Contents

- [Plugin Settings](plugin_settings.md)
- [Project Settings](project_settings.md)
- [Subscription Templates](subscription_template.md)
- [API Endpoints](api_endpoints.md)
- [FIWARE Broker Scripts](broker_scripts.md)
- [cURL Examples](curl_examples.md)
