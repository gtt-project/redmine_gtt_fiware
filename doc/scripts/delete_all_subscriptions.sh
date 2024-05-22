#!/bin/bash

# The base URL for your Orion Context Broker
BROKER_URL=${BROKER_URL:-"http://app.local:1026"}

# The bearer token for authentication
BROKER_TOKEN=${BROKER_TOKEN:-""}

# Define the headers for the cURL commands
HEADERS=(-H "Accept: application/json")
if [ -n "$BROKER_TOKEN" ]; then
  HEADERS+=(-H "Authorization: Bearer $BROKER_TOKEN")
fi

# Fetch all subscription IDs using a GET request
response=$(curl -s -o /dev/null -w "%{http_code}" -X GET "${BROKER_URL}/v2/subscriptions" "${HEADERS[@]}")
http_code="$response"

echo "HTTP Code: $http_code"

# Check if the GET request returned a 401 status code
if [ "$http_code" -eq 401 ]; then
    echo "Unauthorized. Please check your token."
    exit 1
fi

# If the GET request was successful, fetch the response body and parse it to get the subscription IDs
if [ "$http_code" -eq 200 ]; then
    response_body=$(curl -s -X GET "${BROKER_URL}/v2/subscriptions" "${HEADERS[@]}")
    subscription_ids=$(echo "$response_body" | jq -r '.[].id')
fi

# Check if there are any subscriptions to delete
if [ -z "$subscription_ids" ]; then
    echo "No subscriptions to delete."
    exit 0
fi

# Loop through the subscription IDs and delete each one
for id in $subscription_ids; do
  response=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${BROKER_URL}/v2/subscriptions/${id}" "${HEADERS[@]}")
  http_code="$response"

  # Check if the DELETE request returned a 401 status code (optional: just to notify but not to exit)
  if [ "$http_code" -eq 401 ]; then
      echo "Failed to delete subscription $id. Unauthorized. Please check your token."
      continue
  fi

  echo "Deleted subscription $id"
done

echo "All subscriptions have been deleted."
