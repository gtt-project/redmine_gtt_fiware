# FIWARE Broker Scripts

This document describes the scripts available in the `scripts` directory that
help manage the FIWARE context broker.

- [Register All Subscriptions](#register-all-subscriptions)
- [Delete All Subscriptions](#delete-all-subscriptions)

## Register All Subscriptions

**File:** `register_all_subscriptions.sh`

**Description:** This script registers all subscriptions from the context broker
with a Redmine instance. It fetches all subscriptions, filters those with the
`X-Redmine-GTT-Subscription-Template-URL` header, and makes a GET request to the
URL specified in the header for each subscription.

**Usage:**

```bash
./scripts/register_all_subscriptions.sh <api_key>
```

**Arguments:**

- `api_key`: The API key for your Redmine instance. This can also be provided
  through the `REDMINE_API_KEY` environment variable.

**Environment Variables:**

- `REDMINE_API_KEY`: The API key for your Redmine instance. This is used if the
  `api_key` argument is not provided.
- `BROKER_URL`: The base URL for your Orion Context Broker. Defaults to
  `http://app.local:1026` if not set.
- `BROKER_TOKEN`: The bearer token for authentication. If provided, it will be
  used in the `Authorization` header for the requests.
- `FIWARE_SERVICE`: The FIWARE service for the subscriptions (optional).
- `FIWARE_SERVICEPATH`: The FIWARE service path for the subscriptions (optional).

**Note:** Make sure to set the `BROKER_URL` and `BROKER_TOKEN` (optional) environment
variables to your context broker URL and authentication token respectively
before running this script.

To prepend an environment variable to a command in the terminal, you can do so
like this:

```bash
BROKER_URL=your_broker_url ./scripts/register_all_subscriptions.sh <redmine_api_key>
```

Replace `redmine_api_key` with your actual Redmine API key and `your_broker_url`
with the correct URL. This will set the `BROKER_URL` environment variables for
the duration of the `register_all_subscriptions.sh` script.

## Delete All Subscriptions

**File:** `delete_all_subscriptions.sh`

**Description:** This script deletes all subscriptions from the context broker.
It makes a GET request to the `/v2/subscriptions` endpoint to retrieve all
subscriptions, and then makes DELETE requests to the
`/v2/subscriptions/{subscriptionId}` endpoint to delete each one.

**Usage:**

```bash
./scripts/delete_all_subscriptions.sh
```

**Environment Variables:**

- `BROKER_URL`: The base URL for your Orion Context Broker. Defaults to
  `http://app.local:1026` if not set.
- `BROKER_TOKEN`: The bearer token for authentication. If provided, it will be
  used in the `Authorization` header for the requests.
- `FIWARE_SERVICE`: The FIWARE service for the subscriptions (optional).
- `FIWARE_SERVICEPATH`: The FIWARE service path for the subscriptions (optional).

**Note:** This script does not require any arguments. Make sure to set the
`BROKER_URL` and `BROKER_TOKEN` (optional) environment variables to your context
broker URL and authentication token respectively before running this script.

To prepend an environment variable to a command in the terminal, you can do so
like this:

```bash
BROKER_URL=your_broker_url ./scripts/delete_all_subscriptions.sh
```

Replace `your_broker_url` with your actual Redmine API key. This will set the
`BROKER_URL` environment variable for the duration of the
`delete_all_subscriptions.sh` script.
