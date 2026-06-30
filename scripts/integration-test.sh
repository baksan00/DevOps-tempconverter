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

echo "Creating test network..."
podman network create "$NETWORK_NAME"

echo "Starting MySQL container..."
podman run -d \
  --name "$DB_CONTAINER" \
  --network "$NETWORK_NAME" \
  -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASS" \
  -e MYSQL_DATABASE="$DB_NAME" \
  -e MYSQL_USER="$DB_USER" \
  -e MYSQL_PASSWORD="$DB_PASS" \
  docker.io/library/mysql:8

echo "Waiting for MySQL TCP connection..."
for i in {1..90}; do
  if podman exec "$DB_CONTAINER" mysql \
    -h 127.0.0.1 \
    -uroot \
    -p"$DB_ROOT_PASS" \
    -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL accepts TCP connections."
    break
  fi

  if [ "$i" -eq 90 ]; then
    echo "MySQL did not become ready in time."
    podman logs "$DB_CONTAINER"
    exit 1
  fi

  sleep 2
done

echo "Checking non-root database user..."
for i in {1..30}; do
  if podman exec "$DB_CONTAINER" mysql \
    -h 127.0.0.1 \
    -u"$DB_USER" \
    -p"$DB_PASS" \
    "$DB_NAME" \
    -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Non-root MySQL user works."
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "Non-root MySQL user is not ready."
    podman logs "$DB_CONTAINER"
    exit 1
  fi

  sleep 2
done

echo "Starting TempConverter application..."
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

echo "Waiting for application..."
for i in {1..90}; do
  if curl -fsS http://localhost:5050 >/tmp/tc-response.html 2>/dev/null; then
    echo "Application is ready."
    break
  fi

  if ! podman ps --format "{{.Names}}" | grep -q "^${APP_CONTAINER}$"; then
    echo "Application container stopped unexpectedly."
    podman logs "$APP_CONTAINER"
    exit 1
  fi

  if [ "$i" -eq 90 ]; then
    echo "Application did not become ready in time."
    podman logs "$APP_CONTAINER"
    exit 1
  fi

  sleep 2
done

echo "Checking page content..."
curl -fsS http://localhost:5050 | grep -q "Celsius to Fahrenheit Converter"
curl -fsS http://localhost:5050 | grep -q "$STUDENT_NAME"
curl -fsS http://localhost:5050 | grep -q "$COLLEGE_NAME"

echo "Integration test passed."
