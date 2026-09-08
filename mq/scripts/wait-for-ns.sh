#!/bin/bash

set -e

HOST="$1"
PORT="$2"
shift 2

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "Usage: wait-for-ns.sh <host> <port> <command>..."
    exit 1
fi

echo "Waiting for RocketMQ NameServer ${HOST}:${PORT}..."

until bash -c "echo > /dev/tcp/${HOST}/${PORT}" 2>/dev/null; do
    echo "NameServer is not ready, waiting..."
    sleep 2
done

echo "NameServer ${HOST}:${PORT} is ready."

exec "$@"