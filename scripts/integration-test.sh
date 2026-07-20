#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME="tc-test-net"
DB_CONTAINER="tc-test-db"
APP_CONTAINER="tc-test-app"

DB_NAME="${DB_NAME:-tempconverter}"
DB_USER="${DB_USER:-tempuser}"
DB_PASS="${DB_PASS:-temppass}"
DB_ROOT_PASS="${DB_ROOT_PASS:-rootpass}"

STUDENT_NAME="${STUDENT_NAME:?Set STUDENT_NAME before running this script}"
COLLEGE_NAME="${COLLEGE_NAME:?Set COLLEGE_NAME before running this script}"

cleanup() {
  podman rm -f "$APP_CONTAINER" "$DB_CONTAINER" >/dev/null 2>&1 || true
  podman network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup

podman network create "$NETWORK_NAME"

podman run -d \
  --name "$DB_CONTAINER" \
  --network "$NETWORK_NAME" \
  -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASS" \
  -e MYSQL_DATABASE="$DB_NAME" \
  -e MYSQL_USER="$DB_USER" \
  -e MYSQL_PASSWORD="$DB_PASS" \
  docker.io/library/mysql:8

echo "Waiting for MySQL..."
for i in {1..60}; do
  if podman exec "$DB_CONTAINER" mysqladmin ping -uroot -p"$DB_ROOT_PASS" --silent >/dev/null 2>&1; then
    echo "MySQL is ready."
    break
  fi

  if [ "$i" -eq 60 ]; then
    echo "MySQL did not become ready in time."
    podman logs "$DB_CONTAINER"
    exit 1
  fi

  sleep 2
done

podman run -d \
  --name "$APP_CONTAINER" \
  --network "$NETWORK_NAME" \
  -p 5050:5000 \
  -e DB_USER="$DB_USER" \
  -e DB_PASS="$DB_PASS" \
  -e DB_HOST="$DB_CONTAINER" \
  -e DB_NAME="$DB_NAME" \
  -e STUDENT="$STUDENT_NAME" \
  -e COLLEGE="$COLLEGE_NAME" \
  tempconverter:latest

echo "Waiting for app..."
for i in {1..60}; do
  if curl -fsS http://localhost:5050 >/tmp/tc-response.html 2>/dev/null; then
    echo "Application is ready."
    break
  fi

  if [ "$i" -eq 60 ]; then
    echo "Application did not become ready in time."
    podman logs "$APP_CONTAINER"
    exit 1
  fi

  sleep 2
done

curl -fsS http://localhost:5050 | grep -q "Celsius to Fahrenheit Converter"
curl -fsS http://localhost:5050 | grep -q "$STUDENT_NAME"
curl -fsS http://localhost:5050 | grep -q "$COLLEGE_NAME"

echo "Integration test passed."
