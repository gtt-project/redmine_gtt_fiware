# Location Sensor Example

This example demonstrates how to create a location sensor entity and subscribe
to its updates.

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

## Delete Entities

```bash
curl -iX DELETE "${BROKER_URL}/v2/entities/urn:ngsi-ld:LocationSensor:001"
```

## Notes

- Ensure that the FIWARE context broker is running and accessible.
- The coordinates in the location examples are in [longitude, latitude] format.

These cURL commands should help you interact with the FIWARE broker and test the
Redmine GTT FIWARE plugin effectively. If you encounter any issues or need
further assistance, please let us know!