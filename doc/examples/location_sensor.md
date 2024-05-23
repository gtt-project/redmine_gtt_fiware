# Location Sensor Example

This example demonstrates how to create a location sensor entity and subscribe
to its updates.

## Subscription Template for Location Sensor

Create a new subscription template for the location sensor entity with the
following minimal settings:

### General Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Name**    | `Location Alert`                                                |
| **Broker URL** | `your_broker_url` (e.g., `http://127.0.0.1:1026`)            |

### Subscription Settings

| Field               | Value                                                   |
|---------------------|---------------------------------------------------------|
| **Entities**        | `[{ "idPattern": ".*", "type": "LocationSensor" }]`     |
| **Geospatial Query**| Apply the project boundary by clicking "Insert project boundary"|

### Issue Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Subject**       | `Location Alert`                                          |
| **Description**   | `The location sensor ${id} entered the project area.`     |
| **Issue geometry**| `{ "type": "Feature", "geometry": "${location}" }`        |
| **Sent from user**| `api_user` (select the user who will send the issue)      |

Create the subscription template and publish it.

**Note:** When authentication is required, provide the `Authorization` header with

```bash
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
```

## Creating an Entity with Location

```bash
curl -iX POST "${BROKER_URL}/v2/entities" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "urn:ngsi-ld:LocationSensor:001",
    "type": "LocationSensor",
    "location": {
      "value": {
        "type": "Point",
        "coordinates": [135.27666, 34.72483]
      },
      "type": "geo:json"
    }
  }'
```

## Update Location

```bash
curl -iX PATCH \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:LocationSensor:001/attrs" \
  -H "Content-Type: application/json" \
  -d '{
    "location": {
      "value": {
        "type": "Point",
        "coordinates": [139.75032, 35.67087]
      },
      "type": "geo:json"
    }
  }'
```

**Note**: The location coordinates are for Tokyo and Kobe, Japan. In order to
trigger the subscription in this example, the location must be updated to be
within the project boundary.

## Delete Entities

```bash
curl -iX DELETE "${BROKER_URL}/v2/entities/urn:ngsi-ld:LocationSensor:001"
```
