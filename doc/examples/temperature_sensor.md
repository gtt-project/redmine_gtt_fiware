# Temperature Sensor Example

This example demonstrates how to create a temperature sensor entity and
subscribe to its updates.

## Subscription Template for Temperature Sensor

Create a new subscription template for the temperature sensor entity with the
following minimal settings:

### General Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Name**    | `Temperature Alert > 30°C`                                      |
| **Broker URL** | `your_broker_url` (e.g., `http://127.0.0.1:1026`)            |

### Subscription Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Entities** | `[{ "idPattern": ".*", "type": "TemperatureSensor" }]`         |
| **Query**   | `temperature > 30`                                              |

### Issue Settings

| Field             | Value                                                     |
|-------------------|-----------------------------------------------------------|
| **Subject**       | `High Temperature Alert`                                  |
| **Description**   | `The temperature sensor ${id} recorded a temperature of ${temperature}°C.`|
| **Notes**         | `The temperature reading has been updated to ${temperature}°C.`|
| **Threshold (h)** | `24` (new issue if temperature remains high after 24h)    |
| **Sent from user**| `api_user` (select the user who will send the issue)      |

Create the subscription template and publish it.

**Note:** When authentication is required, provide the `Authorization` header with

```bash
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
```

## Creating an Entity with Temperature

```bash
curl -iX POST "${BROKER_URL}/v2/entities" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
  -d '{
    "id": "urn:ngsi-ld:TemperatureSensor:001",
    "type": "TemperatureSensor",
    "temperature": {
      "value": 25.0,
      "type": "Number"
    }
  }'

curl -iX POST "${BROKER_URL}/v2/entities" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
  -d '{
    "id": "urn:ngsi-ld:TemperatureSensor:002",
    "type": "TemperatureSensor",
    "temperature": {
      "value": 25.0,
      "type": "Number"
    }
  }'
```

## Update Temperature

```bash
curl -iX PATCH \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:TemperatureSensor:001/attrs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${BROKER_TOKEN}" \
  -d '{
    "temperature": {
      "value": 28.0,
      "type": "Number"
    }
  }'
```

## Delete Entities

```bash
curl -iX DELETE \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:TemperatureSensor:001" \
  -H "Authorization: Bearer ${BROKER_TOKEN}"
curl -iX DELETE \
  "${BROKER_URL}/v2/entities/urn:ngsi-ld:TemperatureSensor:002" \
  -H "Authorization: Bearer ${BROKER_TOKEN}"
```
