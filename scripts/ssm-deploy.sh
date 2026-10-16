#!/usr/bin/env bash
# Runs on the CI runner (or an operator laptop with AWS credentials).
# Ships the deploy bundle to S3 and runs scripts/deploy.sh on the EC2 instance through
# AWS Systems Manager Run Command - no SSH and no inbound port needed.
#
# Usage: scripts/ssm-deploy.sh <image-tag>
# Env:   AWS_REGION DEPLOY_BUCKET INSTANCE_ID ECR_REGISTRY
set -Eeuo pipefail

TAG="${1:?usage: ssm-deploy.sh <image-tag>}"
: "${AWS_REGION:?}" "${DEPLOY_BUCKET:?}" "${INSTANCE_ID:?}" "${ECR_REGISTRY:?}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Uploading deploy bundle for ${TAG}"
tar -czf "${TMP}/bundle.tgz" -C "$ROOT" docker-compose.prod.yml monitoring scripts/deploy.sh
aws s3 cp "${TMP}/bundle.tgz" "s3://${DEPLOY_BUCKET}/releases/${TAG}/bundle.tgz" \
  --region "$AWS_REGION" --only-show-errors

jq -n --arg bucket "$DEPLOY_BUCKET" --arg tag "$TAG" --arg region "$AWS_REGION" --arg reg "$ECR_REGISTRY" '{
  commands: [
    "set -euo pipefail",
    "mkdir -p /opt/todoapp && cd /opt/todoapp",
    ("aws s3 cp s3://" + $bucket + "/releases/" + $tag + "/bundle.tgz bundle.tgz --region " + $region + " --only-show-errors"),
    "tar -xzf bundle.tgz && rm -f bundle.tgz",
    ("IMAGE_TAG=" + $tag + " ECR_REGISTRY=" + $reg + " AWS_REGION=" + $region + " bash /opt/todoapp/scripts/deploy.sh")
  ]
}' > "${TMP}/params.json"

echo "==> Sending SSM command to ${INSTANCE_ID}"
CMD_ID="$(aws ssm send-command --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "todoapp deploy ${TAG}" \
  --timeout-seconds 900 \
  --parameters "file://${TMP}/params.json" \
  --query Command.CommandId --output text)"
echo "Command id: ${CMD_ID}"

STATUS="Pending"
for _ in $(seq 1 180); do
  STATUS="$(aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || echo Pending)"
  case "$STATUS" in
    Success|Failed|Cancelled|TimedOut) break ;;
  esac
  sleep 5
done

echo "==> Remote output"
aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" --query StandardOutputContent --output text || true
echo "==> Remote errors"
aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$CMD_ID" \
  --instance-id "$INSTANCE_ID" --query StandardErrorContent --output text || true

if [[ "$STATUS" != "Success" ]]; then
  echo "Deployment failed with status: ${STATUS}" >&2
  exit 1
fi
echo "Deployment command finished successfully"
