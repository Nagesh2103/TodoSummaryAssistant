# Failure and rollback scenarios

Release unit = an immutable pair of images `todo-backend:<sha12>` and `todo-frontend:<sha12>` in ECR.
The EC2 host remembers the last healthy tag in `/opt/todoapp/.current_tag`. Every rollback is simply
"deploy a previous tag" through the same automated path.

## 1. A faulty version is deployed - how do I roll back?

**Automatic (bad release fails its health check).** `scripts/deploy.sh` brings the new tag up and then
gates on three checks (`/healthz` = `{"status":"UP"}` incl. the RDS connection, `/`, and `/api/todos`).
If they do not pass within ~150 s it re-deploys the previous tag from `.current_tag`, re-checks,
and exits non-zero so the pipeline run is red. Users are served by the old version again; the
failed tag stays in ECR for analysis.

**Manual (bad release passes health checks but is functionally wrong).**

1. GitHub -> Actions -> *Rollback / redeploy a previous version* -> Run workflow, enter the last good
   12-char SHA (visible in earlier green runs or `aws ecr describe-images`). It verifies the tag exists,
   redeploys through SSM and smoke-tests `APP_URL`. Typical time: 2-3 minutes.
2. Then `git revert <bad-commit>` on `main` so the next push does not redeploy the bug.

**Database note.** Hibernate `ddl-auto=update` only adds columns/tables, so rolling the application
back is safe for additive changes. A destructive schema change must follow expand/contract (additive
release first, cleanup later) or be restored from an RDS snapshot (scenario 6).

## 2. The application crashes after deployment - what happens?

* The container has `restart: unless-stopped`: Docker restarts a crashed JVM automatically
  (`-XX:+ExitOnOutOfMemoryError` turns OOM into a clean exit that gets restarted, instead of a zombie JVM).
* During the pipeline: the health gate fails -> automatic rollback (scenario 1).
* After the pipeline (runtime crash): `BackendDown` (critical, 1 min) fires; `ContainerCrashLoop` fires
  if it restarts more than twice in 15 min. The dashboard shows *Container restarts* and *uptime*.
* Investigation: `aws ssm start-session`, then `docker logs --tail 200 todo-backend`, `docker inspect todo-backend --format '{{.State.OOMKilled}} {{.State.ExitCode}}'`.
* If a restart loop persists after a deploy, run the rollback workflow.
* nginx keeps serving the SPA and returns 502 for `/api` while the backend is down; it recovers on its
  own because it re-resolves the backend at request time.

## 3. The CI/CD tool is unavailable - can I still deploy?

Yes, nothing about deployment depends on GitHub being up:

1. **From a laptop with AWS credentials (SSO/admin role):**
   `AWS_REGION=ap-south-1 DEPLOY_BUCKET=... INSTANCE_ID=... ECR_REGISTRY=... scripts/ssm-deploy.sh <tag>`
   (uses the same SSM path and the same health-gated, auto-rolling-back `deploy.sh`).
2. **Directly on the host (break-glass, no GitHub, no S3):** `aws ssm start-session --target <id>`, then
   `cd /opt/todoapp && sudo IMAGE_TAG=<tag> ECR_REGISTRY=<acct>.dkr.ecr.<region>.amazonaws.com AWS_REGION=<region> bash scripts/deploy.sh`.
   The last bundle (compose file, monitoring config, script) is already on disk from the previous release.
3. If ECR is also down, images already on the host can be started with `docker compose up -d` using the
   tag in `.current_tag`.

Images are built in the CI, so building a *new* version without CI requires building locally and pushing
to ECR manually (`docker build` + `docker push`), then using option 1 or 2.

## 4. Secrets are leaked - what steps do I take?

1. **Contain** - identify the secret (Cohere key, Slack webhook, DB password, Grafana password, AWS credentials).
2. **Rotate/revoke first, investigate second:**
   * Cohere key: revoke in the Cohere dashboard, create a new one.
   * Slack webhook: delete and re-create the webhook in the Slack app settings.
   * DB password: `aws rds modify-db-instance --manage-master-user-password --rotate-master-user-password --apply-immediately`
     (RDS-managed rotation in Secrets Manager).
   * Grafana: change the password and update the SSM parameter.
   * AWS access: there are no static keys by design. If a role/session is suspected, attach an explicit
     deny / revoke sessions on the role (IAM -> role -> *Revoke active sessions*) and review CloudTrail.
3. **Update the source of truth** - `aws ssm put-parameter --overwrite ...` for the new value.
4. **Redeploy** the current tag (rollback workflow with the current SHA) so containers pick up the new values
   (secrets are read at deploy time).
5. **If it was committed to git** - rotation is mandatory (history is public to everyone with access);
   also remove it from history (`git filter-repo`/BFG) and force-push; the CI runs gitleaks to catch
   new occurrences.
6. **Investigate** - CloudTrail, RDS and Slack audit logs for use of the leaked value; document the incident
   and add a detective control if the leak path was a gap.

## 5. The EC2 instance fails - how do I recover?

The instance is **cattle**: it holds no state that is not reproducible. State lives in RDS (data),
ECR (images), SSM/Secrets Manager (config), S3 (bundles). Only Prometheus/Grafana history on local
volumes is lost (7-day retention, non-critical).

* *Instance impaired / host failure*: EC2 status-check recovery or stop/start moves it to new hardware;
  the Elastic IP, role and security groups are retained and containers restart (`restart: unless-stopped`).
* *Instance lost or corrupted*: `terraform apply -replace=aws_instance.app` (or launch a new instance
  with the same user data and role), re-associate the Elastic IP, then run the pipeline (or
  `scripts/ssm-deploy.sh <last-good-tag>`). `user-data` installs Docker, Compose and swap; `deploy.sh`
  pulls images and config. RTO is roughly 10-15 minutes, RPO is zero for application data.
* *AZ outage*: the same `terraform apply` with a subnet in another AZ (RDS Multi-AZ covers the database
  side). A real HA design puts two instances behind an ALB - listed as a next step.
* Alert: `BackendDown` fires (Prometheus is on the same host, so also set an external uptime check
  or a CloudWatch alarm on `StatusCheckFailed` - see MONITORING_AND_OPERATIONS.md).

## 6. The RDS database becomes unavailable - impact and recovery

**Impact.** The API cannot read or write todos: list/create/update/delete and `/summarize` return
HTTP 500. `/healthz` reports DOWN (the DB indicator is part of the aggregate), so a deploy attempted during
the outage fails fast and rolls back instead of going live broken. The static UI still loads and shows
error notifications. Alerts: `DatabaseConnectionTimeouts` and `HighErrorRate`. Hikari re-establishes
connections automatically when the DB returns - no app restart is needed.

**Recovery plan.**

| Cause | Action |
|---|---|
| Instance reboot / maintenance | wait; Hikari reconnects. With **Multi-AZ** (`db_multi_az = true`) RDS fails over to the standby in ~60-120 s automatically |
| Connectivity (SG/route/credentials changed) | check `rds-sg` ingress still references `app-sg`, secret value vs. rotation, `aws rds describe-events` |
| Storage full | `aws rds modify-db-instance --allocated-storage ...` (enable storage autoscaling in real use) |
| Data corruption or bad migration | **point-in-time restore** to a new instance (automated backups, 7 days, RPO ~5 min): `aws rds restore-db-instance-to-point-in-time ...`, then update `/todoapp/prod/db_endpoint` (+ `db_secret_arn` if changed) and redeploy |
| Instance lost | restore from the latest automated backup/snapshot the same way; take a manual snapshot before risky changes |

Backups: automated daily backups + transaction logs (retention 7 days, configurable
`db_backup_retention_days`), encrypted storage, snapshots copy tags. Assessment default is single-AZ to stay
in the free tier; production recommendation is Multi-AZ + deletion protection + a final snapshot.
