#!/bin/bash

# The API key for Redmine
REDMINE_API_KEY=${REDMINE_API_KEY:-$1}

# Check if API key is provided
if [ -z "$REDMINE_API_KEY" ]
then
  echo "No API key provided. Usage: ./register_all_subscriptions.sh <api_key> or set the REDMINE_API_KEY environment variable."
  exit 1
fi

# The base URL for your Orion Context Broker
BROKER_URL=${BROKER_URL:-"http://app.local:1026"}

# Fetch all subscriptions using a GET request
subscriptions=$(curl -s -X GET "${BROKER_URL}/v2/subscriptions" -H "Accept: application/json")

# Use jq to parse the JSON response and filter subscriptions with the "X-Redmine-GTT-Subscription-Template-URL" header
filtered_subscriptions=$(echo "$subscriptions" | jq -c '.[] | select(.notification.httpCustom.headers."X-Redmine-GTT-Subscription-Template-URL" != null)')

# Check if there are any filtered subscriptions
if [ -z "$filtered_subscriptions" ]; then
  echo "No subscriptions with the 'X-Redmine-GTT-Subscription-Template-URL' header found."
  exit 0
fi

# Loop through the filtered subscriptions
echo "$filtered_subscriptions" | while read -r subscription; do
  # Extract the URL and append the subscription id
  url=$(echo "$subscription" | jq -r '(.notification.httpCustom.headers."X-Redmine-GTT-Subscription-Template-URL" + .id)')

  # Execute a GET request to the URL
  response=$(curl -s -X GET "$url" -H "X-Redmine-API-Key: $REDMINE_API_KEY")

  # Print a log message
  echo "GET request to $url completed with response: $response"
done
