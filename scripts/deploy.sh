#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_ENV:?DEPLOY_ENV is required}"
: "${IMAGE:?IMAGE is required}"

APP_URL="${APP_URL:-http://localhost:8000}"
CONTAINER_NAME="cicd-pipeline-demo-${DEPLOY_ENV}"
HEALTH_URL="${APP_URL%/}/health"

echo "Deploying ${IMAGE} to ${DEPLOY_ENV}"

if command -v docker >/dev/null 2>&1; then
  docker pull "${IMAGE}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -e APP_ENV="${DEPLOY_ENV}" \
    -p 8000:8000 \
    "${IMAGE}"
else
  echo "Docker is not available on this runner. Skipping local container replacement."
fi

echo "Checking health endpoint: ${HEALTH_URL}"
for attempt in {1..10}; do
  if curl --fail --silent --show-error "${HEALTH_URL}" >/tmp/health-response.json; then
    echo "Deployment health check passed"
    cat /tmp/health-response.json
    {
      echo "health_url=${HEALTH_URL}"
      echo "status=success"
    } >>"${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi

  echo "Health check attempt ${attempt} failed; retrying..."
  sleep 5
done

echo "Deployment health check failed"
echo "status=failure" >>"${GITHUB_OUTPUT:-/dev/null}"
exit 1
