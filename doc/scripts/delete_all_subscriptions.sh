#!/bin/bash

# The base URL for your Orion Context Broker
BROKER_URL=${BROKER_URL:-"http://app.local:1026"}

# Fetch all subscription IDs using a GET request
# Include additional headers as needed, e.g., for multi-tenant setups or authentication
subscription_ids=$(curl -s -X GET "${BROKER_URL}/v2/subscriptions" \
-H "Accept: application/json" | jq -r '.[].id')

# Check if there are any subscriptions to delete
if [ -z "$subscription_ids" ]; then
    echo "No subscriptions to delete."
    exit 0
fi

# Loop through the subscription IDs and delete each one
for id in $subscription_ids; do
    curl -X DELETE "${BROKER_URL}/v2/subscriptions/${id}" \
    -H "Accept: application/json"
    echo "Deleted subscription $id"
done

echo "All subscriptions have been deleted."

