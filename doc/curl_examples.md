# cURL Examples

This section provides examples of how to interact with the FIWARE Broker using cURL.

## Prerequisites

Before running the cURL commands, make sure you have the following:

- The FIWARE context broker URL.
- An entity type (e.g., `TemperatureSensor` for temperature and `LocationSensor`
  for location).

```bash
export BROKER_URL="your_broker_url"
```

Replace `your_broker_url` with the actual URL of your FIWARE broker. After
running this command, the BROKER_URL environment variable will be
available to all subsequent commands in the same terminal session.

### Entity Types

In this walkthrough, we will be using two entity types:

- `TemperatureSensor`: Represents sensors that measure temperature.
- `LocationSensor`: Represents sensors that provide location data.

### Creating an Entity with Temperature

```bash
curl -iX POST \
  'http://${BROKER_URL}/v2/entities' \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "urn:ngsi-ld:TemperatureSensor:001",
    "type": "TemperatureSensor",
    "temperature": {
      "value": 25.0,
      "type": "Number"
    }
  }'
```

### Creating an Entity with Location

```bash
curl -iX POST \
  'http://${BROKER_URL}/v2/entities' \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "urn:ngsi-ld:LocationSensor:001",
    "type": "LocationSensor",
    "location": {
      "value": {
        "type": "Point",
        "coordinates": [40.418889, -3.691944]
      },
      "type": "geo:json"
    }
  }'
```

## Example cURL Commands

### Update Temperature

```bash
curl -iX PATCH \
  'http://${BROKER_URL}/v2/entities/urn:ngsi-ld:TemperatureSensor:001/attrs' \
  -H 'Content-Type: application/json' \
  -d '{
    "temperature": {
      "value": 28.0,
      "type": "Number"
    }
  }'
```

### Update Location

```bash
curl -iX PATCH \
  'http://${BROKER_URL}/v2/entities/urn:ngsi-ld:LocationSensor:001/attrs' \
  -H 'Content-Type: application/json' \
  -d '{
    "location": {
      "value": {
        "type": "Point",
        "coordinates": [41.376944, 2.185556]
      },
      "type": "geo:json"
    }
  }'
```

### Get Entities

```bash
curl -iX GET \
  'http://${BROKER_URL}/v2/entities' \
  -H 'Accept: application/json'
```

### Get Subscriptions

```bash
curl -iX GET \
  'http://${BROKER_URL}/v2/subscriptions' \
  -H 'Accept: application/json'
```

## Notes

- Ensure that the FIWARE context broker is running and accessible.
- The coordinates in the location examples are in [longitude, latitude] format.

These cURL commands should help you interact with the FIWARE broker and test the
Redmine GTT FIWARE plugin effectively. If you encounter any issues or need
further assistance, please let me know!
