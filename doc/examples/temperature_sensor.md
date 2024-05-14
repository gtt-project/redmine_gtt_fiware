# Temperature Sensor Example

This example demonstrates how to create a temperature sensor entity and
subscribe to its updates.

## Creating an Entity with Temperature

```bash
curl -iX POST "${BROKER_URL}/v2/entities" \
  -H "Content-Type: application/json" \
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
  -d '{
    "temperature": {
      "value": 28.0,
      "type": "Number"
    }
  }'
```

## Delete Entities

```bash
curl -iX DELETE "${BROKER_URL}/v2/entities/urn:ngsi-ld:TemperatureSensor:001"
curl -iX DELETE "${BROKER_URL}/v2/entities/urn:ngsi-ld:TemperatureSensor:002"
```
