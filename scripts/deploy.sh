#!/usr/bin/env bash
# Runs ON the EC2 instance (invoked by AWS SSM Run Command from the pipeline, or by an
# operator through Session Manager). Idempotent: safe to re-run for any image tag.
#
# Required env:  IMAGE_TAG  ECR_REGISTRY  AWS_REGION
# Optional env:  APP_DIR (default /opt/todoapp)  SSM_PREFIX (default /todoapp/prod)
#
# Secrets are read at deploy time from SSM Parameter Store / Secrets Manager using the
# instance's IAM role, exported to this process only, and never written to disk.
set -Eeuo pipefail

: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${ECR_REGISTRY:?ECR_REGISTRY is required}"
: "${AWS_REGION:?AWS_REGION is required}"
APP_DIR="${APP_DIR:-/opt/todoapp}"
SSM_PREFIX="${SSM_PREFIX:-/todoapp/prod}"
COMPOSE=(docker compose -f "${APP_DIR}/docker-compose.prod.yml" -p todoapp)

log() { echo "[$(date -u +%FT%TZ)] $*"; }
get_param() {
  aws ssm get-parameter --region "$AWS_REGION" --name "${SSM_PREFIX}/$1" \
    --with-decryption --query Parameter.Value --output text
}

cd "$APP_DIR"

log "Loading configuration for tag ${IMAGE_TAG}"
DB_ENDPOINT="$(get_param db_endpoint)"
DB_NAME="$(get_param db_name)"
DB_SECRET_ARN="$(get_param db_secret_arn)"
DB_SECRET_JSON="$(aws secretsmanager get-secret-value --region "$AWS_REGION" \
  --secret-id "$DB_SECRET_ARN" --query SecretString --output text)"

SPRING_DATASOURCE_USERNAME="$(jq -r .username <<<"$DB_SECRET_JSON")"
SPRING_DATASOURCE_PASSWORD="$(jq -r .password <<<"$DB_SECRET_JSON")"
SPRING_DATASOURCE_URL="jdbc:mysql://${DB_ENDPOINT}:3306/${DB_NAME}?sslMode=REQUIRED&serverTimezone=UTC"
COHERE_API_KEY="$(get_param cohere_api_key)"
SLACK_WEBHOOK_URL="$(get_param slack_webhook_url)"
GF_SECURITY_ADMIN_PASSWORD="$(get_param grafana_admin_password)"
export SPRING_DATASOURCE_USERNAME SPRING_DATASOURCE_PASSWORD SPRING_DATASOURCE_URL \
       COHERE_API_KEY SLACK_WEBHOOK_URL GF_SECURITY_ADMIN_PASSWORD ECR_REGISTRY

PREV_TAG="$(cat "${APP_DIR}/.current_tag" 2>/dev/null || true)"
log "Previous tag: ${PREV_TAG:-<none>}"

log "Logging in to ECR ${ECR_REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

# Pre-flight: fail before touching the running stack if the image tag does not exist
export IMAGE_TAG
log "Pulling images"
"${COMPOSE[@]}" pull --quiet backend frontend

health_check() {
  # Gate: aggregated actuator health (includes the RDS connection), SPA, and an API call that hits the DB
  local i
  for i in $(seq 1 30); do
    if curl -fsS --max-time 5 http://127.0.0.1/healthz 2>/dev/null | grep -q '"status":"UP"' \
       && curl -fsS --max-time 5 -o /dev/null http://127.0.0.1/ \
       && curl -fsS --max-time 10 -o /dev/null http://127.0.0.1/api/todos; then
      return 0
    fi
    log "Health check attempt ${i}/30 not ready yet"
    sleep 5
  done
  return 1
}

log "Starting stack"
"${COMPOSE[@]}" up -d --remove-orphans

if health_check; then
  echo "${IMAGE_TAG}" > "${APP_DIR}/.current_tag"
  log "Deployment of ${IMAGE_TAG} is healthy"
  docker image prune -af --filter "until=168h" >/dev/null || true
  "${COMPOSE[@]}" ps
  exit 0
fi

log "ERROR: health check failed for ${IMAGE_TAG}"
"${COMPOSE[@]}" ps || true
docker logs --tail 80 todo-backend 2>&1 || true

if [[ -n "$PREV_TAG" && "$PREV_TAG" != "$IMAGE_TAG" ]]; then
  log "Rolling back to ${PREV_TAG}"
  export IMAGE_TAG="$PREV_TAG"
  "${COMPOSE[@]}" pull --quiet backend frontend || true
  "${COMPOSE[@]}" up -d --remove-orphans
  if health_check; then
    log "Rollback to ${PREV_TAG} succeeded (the failed release is NOT live)"
  else
    log "CRITICAL: rollback to ${PREV_TAG} is also unhealthy - manual intervention required"
  fi
else
  log "No previous release to roll back to"
fi
exit 1
