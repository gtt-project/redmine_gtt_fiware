# Redmine GTT FIWARE Plugin Documentation

This documentation provides detailed instructions on how to use the Redmine GTT
FIWARE plugin and its API endpoints.

## First Steps

- Make sure REST web services is enabled: <http://localhost:3000/settings?tab=api>
- Enable the plugin in project settings
- For security reasons don't select a user with admin rights for the FIWARE
  subscriptions. Instead, create a new user with the necessary permissions.

If you need a test installation of FIWARE, you can use
[FIWARE-Small-Bang](https://github.com/lets-fiware/FIWARE-Small-Bang) (for local
development) or [FIWARE-Big-Bang](https://github.com/lets-fiware/FIWARE-Big-Bang)
(for server deployment).

### Redmine Permissions

![Plugin permissions](permissions.png)

To allow **public** access to NGSI-LD context documents, it's necessary to grant
*View* permissions to the *Anonymous* role.

## How to use

- [Plugin Settings](plugin_settings.md)
- [Project Settings](project_settings.md)
- [Subscription Templates](subscription_template.md)
- [API Endpoints](api_endpoints.md)

## Tools and Utilities

- [FIWARE Broker Scripts](broker_scripts.md)

## Examples and Tutorials

- [Temperature Sensor Example](examples/temperature_sensor.md)
- [Location Sensor Example](examples/location_sensor.md)
- [Street Camera Sensor Example](examples/camera_sensor.md)

For all examples, the following environment variables are used:

```bash
export BROKER_URL="http://your_broker:1026"
```

Replace `your_broker_url` with the actual URL of your FIWARE broker. After
running this command, the BROKER_URL environment variable will be
available to all subsequent commands in the same terminal session.

### General FIWARE Broker Commands

#### Get Entities

```bash
curl -sX GET "${BROKER_URL}/v2/entities" -H "Accept: application/json" | jq
```

#### Get Subscriptions

```bash
curl -sX GET "${BROKER_URL}/v2/subscriptions" -H "Accept: application/json" | jq
```

### Notes

- Ensure that the FIWARE context broker is running and accessible.
- The coordinates in the location examples are in `[longitude, latitude]` format.
- The `jq` command is used to format the JSON output for better readability.

These cURL commands should help you interact with the FIWARE broker and test the
Redmine GTT FIWARE plugin effectively. If you encounter any issues or need
further assistance, please let us know!

#### CORS Issues

If you encounter CORS issues, for example when you use FIWARE-Big-Bang, you can extend
the Ngix configuration as follows:

```nginx
[snip]

server {
  [snip]

  # Add CORS Headers
  add_header 'Access-Control-Allow-Origin' '*' always;
  add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT, PATCH' always;
  add_header 'Access-Control-Allow-Headers' 'Origin, Content-Type, Accept, Authorization, X-Requested-With, fiware-service, fiware-servicepath' always;
  add_header 'Access-Control-Expose-Headers' 'location, fiware-correlator' always;

  location / {
    if ($request_method = 'OPTIONS') {
      add_header 'Access-Control-Allow-Origin' '*' always;
      add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, DELETE, PUT, PATCH' always;
      add_header 'Access-Control-Allow-Headers' 'Origin, Content-Type, Accept, Authorization, X-Requested-With, fiware-service, fiware-servicepath' always;
      add_header 'Access-Control-Expose-Headers' 'location, fiware-correlator' always;
      add_header 'Access-Control-Max-Age' 1728000;
      add_header 'Content-Type' 'text/plain charset=UTF-8';
      add_header 'Content-Length' 0;
      return 204;
    }

    [snip]
  }

  [snip]
}
```

In particular `location` and `fiware-service, fiware-servicepath` are important
for the FIWARE broker to work correctly.
