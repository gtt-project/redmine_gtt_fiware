# Speed Camera Sensor Example

This example demonstrates how to create a street camera sensor entity and
subscribe to its updates.

## Subscription Template for Speed Camera Sensor

Create a new subscription template for the speed camera sensor entity with the
following minimal settings:

### General Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Name**          | `Speed Alert > 80 km/h`                                   |
| **Broker URL**    | `your_broker_url` (e.g., `http://127.0.0.1:1026`)         |

### Subscription Settings

| Field               | Value                                                   |
|---------------------|---------------------------------------------------------|
| **Entities**        | `[{ "idPattern": ".*", "type": "SpeedCameraSensor" }]`  |
| **Query**           | `speed > 80`                                            |

### Issue Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Subject**       | `Speed Alert from ${id}`                                  |
| **Description**   | `The speed camera sensor ${id} detected a speed of ${speed} km/h.`|
| **Issue geometry**| `{ "type": "Feature", "geometry": "${location}" }`        |
| **Attachments**   | `[{"filename": "SC_${timestamp}.jpg", "url": "${image}"}]`|
| **Sent from user**| `api_user` (select the user who will send the issue)      |

Create the subscription template and publish it.

**Note:** When authentication is required, provide the `Authorization` header with

```bash
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
```

## Creating an Entity with Speed Camera

```bash
curl -iX POST "${BROKER_URL}/v2/entities" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
  -H "Fiware-Service: ${FIWARE_SERVICE}" \
  -H "Fiware-ServicePath: ${FIWARE_SERVICEPATH}" \
  -d '{
    "id": "urn:ngsi-ld:SpeedCameraSensor:001",
    "type": "SpeedCameraSensor",
    "image": {
      "value": "[https://images.unsplash.com/photo-1567333188258-99e13c119241%3Fw%3D640](https://private-user-images.githubusercontent.com/227762/354205255-bc50ba25-9f69-464d-b899-eb97ab76e0bf.jpg?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3MjI1MTIyMjcsIm5iZiI6MTcyMjUxMTkyNywicGF0aCI6Ii8yMjc3NjIvMzU0MjA1MjU1LWJjNTBiYTI1LTlmNjktNDY0ZC1iODk5LWViOTdhYjc2ZTBiZi5qcGc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjQwODAxJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI0MDgwMVQxMTMyMDdaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT01M2RlZDUxZWU4NTE2MTlmZjZmMTgxOWQxOWU4MWMyMWMwNzlmZGEzYjgzYmVhZjA5N2YzZjg4ZGVhNDUxNDExJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCZhY3Rvcl9pZD0wJmtleV9pZD0wJnJlcG9faWQ9MCJ9.GEF-0OQ_Uk3dwibSJZfU4n3EQiTBAuRDS1gB1hEL1h0)",
      "type": "URL"
    },
    "speed": {
      "value": 50,
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
      "value": "2024-05-14T12:00:00Z",
      "type": "DateTime"
    }
  }'
```

## Update Speed

```bash
curl -iX PATCH \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:SpeedCameraSensor:001/attrs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
  -H "Fiware-Service: ${FIWARE_SERVICE}" \
  -H "Fiware-ServicePath: ${FIWARE_SERVICEPATH}" \
  -d '{
    "speed": {
      "value": 90.0,
      "type": "Number"
    }
  }'
```

## Delete Entities

```bash
curl -iX DELETE \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:SpeedCameraSensor:001" \
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
  -H "Fiware-Service: ${FIWARE_SERVICE}" \
  -H "Fiware-ServicePath: ${FIWARE_SERVICEPATH}"
```
