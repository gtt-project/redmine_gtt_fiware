# Speed Camera Sensor Example

This example demonstrates how to create a street camera sensor entity and
subscribe to its updates.

## Creating an Entity with Speed Camera

```bash
curl -iX POST "${BROKER_URL}/v2/entities" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "urn:ngsi-ld:SpeedCameraSensor:001",
    "type": "SpeedCameraSensor",
    "image": {
      "value": "https://images.unsplash.com/photo-1567333188258-99e13c119241%3Fw%3D640",
      "type": "URL"
    },
    "speed": {
      "value": 87,
      "type": "Number"
    },
    "location": {
      "value": {
        "type": "Point",
        "coordinates": [135.27666, 34.72483]
      },
      "type": "geo:json"
    },
    "timestamp": {
      "value": "2021-09-01T12:00:00Z",
      "type": "DateTime"
    }
  }'
```

## Update Speed

```bash
curl -iX PATCH \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:SpeedCameraSensor:001/attrs" \
  -H "Content-Type: application/json" \
  -d '{
    "speed": {
      "value": 90.0,
      "type": "Number"
    }
  }'
```

## Delete Entities

```bash
curl -iX DELETE "${BROKER_URL}/v2/entities/urn:ngsi-ld:SpeedCameraSensor:001"
```

## Notes

- Ensure that the FIWARE context broker is running and accessible.
- The coordinates in the location examples are in [longitude, latitude] format.

These cURL commands should help you interact with the FIWARE broker and test the
Redmine GTT FIWARE plugin effectively. If you encounter any issues or need
further assistance, please let us know!
