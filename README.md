# Todo Summary Assistant - DevOps delivery pipeline

A full-stack app (React + Spring Boot + MySQL) to manage to-dos, summarise pending ones with Cohere and post
the summary to Slack. This repository is the original project **plus a production-style delivery pipeline**:
Docker, GitHub Actions CI/CD, AWS EC2 + RDS, and Prometheus + Grafana monitoring.

![Architecture](aws/architecture-diagram.png)

## Table of contents

1. [Repository layout](#repository-layout)
2. [Local run (project understanding)](#1-project-understanding-and-local-execution)
3. [Docker design](#2-containerization-docker)
4. [CI/CD pipeline](#3-cicd-pipeline)
5. [AWS deployment](#4-aws-deployment-ec2--rds)
6. [Monitoring](#5-monitoring-prometheus--grafana)
7. [Failure, rollback, operations](#6-failure-rollback-and-operations-docs)
8. [Tests](#tests)
9. [Changes made to application code](#changes-made-to-application-code)
10. [Assumptions](#assumptions)

## Repository layout

```
Backend/todo-summary-assistant/   Spring Boot + Maven app   (+ Dockerfile, .dockerignore, tests)
Frontend/todo/                    React app                 (+ Dockerfile, nginx.conf.template, .dockerignore, tests)
.github/workflows/ci-cd.yml       CI/CD pipeline            .github/workflows/rollback.yml  one-click rollback
aws/                              architecture-diagram.png, aws-setup.md, iac/ (Terraform)
monitoring/                       prometheus.yml, alert-rules.yml (+ .test.yml), grafana-dashboard.json, provisioning
scripts/                          deploy.sh (on EC2), ssm-deploy.sh (runner), ec2-user-data.sh
docker-compose.yml                local stack (MySQL + app + Prometheus + Grafana + exporters)
docker-compose.prod.yml           EC2 stack (images from ECR, database = RDS)
.env.example                      every environment variable
FAILURE_AND_ROLLBACK.md           MONITORING_AND_OPERATIONS.md
```

## 1. Project understanding and local execution

**Runtime requirements**

| Part | Requirement |
|---|---|
| Backend | Java 17, Maven 3.9 (or `./mvnw`), Spring Boot 3.4.5, port 8080 |
| Frontend | Node 20, npm; React 19 / react-scripts 5, dev port 3000 |
| Database | MySQL 8 (JPA `ddl-auto=update` creates the `todo` table) |
| External | Cohere API key (summarise), Slack Incoming Webhook (post) - both optional for CRUD |

**Environment variables** (full list with comments: [`.env.example`](.env.example))

| Variable | Purpose |
|---|---|
| `SPRING_DATASOURCE_URL` / `_USERNAME` / `_PASSWORD` | database (MySQL locally, RDS in AWS) |
| `COHERE_API_KEY`, `SLACK_WEBHOOK_URL` | secrets, default empty |
| `CORS_ALLOWED_ORIGINS` | only if UI and API are on different origins (default `http://localhost:3000`) |
| `SPRING_JPA_HIBERNATE_DDL_AUTO`, `SPRING_JPA_SHOW_SQL`, `SERVER_PORT`, `JAVA_OPTS` | tuning |
| `REACT_APP_API_BASE_URL` | build-time API base for the UI (default relative `/api`) |
| `BACKEND_URL`, `DNS_RESOLVER` | runtime config of the nginx container |

### Option A - everything in Docker (recommended)

```bash
cp .env.example .env                 # set MYSQL_ROOT_PASSWORD, GRAFANA_ADMIN_PASSWORD, optional keys
docker compose up --build
```

| URL | What |
|---|---|
| http://localhost:3000 | UI (nginx proxies `/api` to the backend) |
| http://localhost:8080/actuator/health , `/actuator/prometheus` | backend health / metrics |
| http://localhost:9090 | Prometheus |
| http://localhost:3001 | Grafana (user `admin`, password from `.env`) - dashboard *Todo Summary Assistant - Overview* |

### Option B - run from source

```bash
# 1. MySQL (or use: docker run -d -p 3306:3306 -e MYSQL_ROOT_PASSWORD=change_me -e MYSQL_DATABASE=todo_db mysql:8.4)
# 2. Backend
cd Backend/todo-summary-assistant
export SPRING_DATASOURCE_PASSWORD=change_me COHERE_API_KEY=... SLACK_WEBHOOK_URL=...
./mvnw spring-boot:run               # http://localhost:8080
# 3. Frontend (the dev server proxies /api to :8080 via the "proxy" field in package.json)
cd Frontend/todo && npm ci && npm start    # http://localhost:3000
```

Cohere and Slack setup are unchanged: create a Cohere key and a Slack Incoming Webhook and provide them
as `COHERE_API_KEY` / `SLACK_WEBHOOK_URL`.

## 2. Containerization (Docker)

Files: `Backend/todo-summary-assistant/Dockerfile`, `Frontend/todo/Dockerfile`, both `.dockerignore`, `Frontend/todo/nginx.conf.template`.

| Decision | Reason |
|---|---|
| **Multi-stage builds** | backend: `maven:3.9-eclipse-temurin-17` builds the jar, runtime is `eclipse-temurin:17-jre-alpine` (JRE only, no Maven/JDK/sources). frontend: `node:20-alpine` builds the bundle, runtime is `nginx-unprivileged:alpine` serving static files (no Node, no `node_modules`) |
| **Non-root** | backend runs as UID 10001 (`USER 10001:10001`); frontend uses the official *unprivileged* nginx image (UID 101, listens on 8080, no capabilities needed) |
| **Small images** | alpine bases, JRE not JDK, `.dockerignore` excludes `target/`, `node_modules`, `.git`, env files; BuildKit cache mounts keep rebuilds fast without bloating layers |
| **Config via environment** | the same image runs everywhere. Spring reads `SPRING_DATASOURCE_*`, `COHERE_API_KEY`, ...; nginx reads `BACKEND_URL` at start (envsubst template). The React bundle uses a *relative* `/api` so it needs no per-environment rebuild |
| **Health checks** | `HEALTHCHECK` on both images (`/actuator/health/liveness`, `/`), used by compose `depends_on: service_healthy` |
| **Graceful shutdown** | `exec java ...` makes the JVM PID 1 so it receives SIGTERM; `server.shutdown=graceful` |
| **JVM in containers** | `-XX:MaxRAMPercentage` honours container memory limits; `-XX:+ExitOnOutOfMemoryError` lets Docker restart a dead JVM |
| **No secrets in images** | nothing sensitive is copied in; `.dockerignore` excludes `.env*` |
| **Security headers / hidden version** | nginx sends `nosniff`, `X-Frame-Options`, `server_tokens off`; only `/api/*` and `/healthz` reach the backend, so `/actuator/*` is not public |

The database is **not** containerised for production (RDS). `docker-compose.yml` includes a MySQL container
for local development only; `docker-compose.prod.yml` has none.

## 3. CI/CD pipeline

File: [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml). Triggers: push to `main`, pull requests to `main`, manual dispatch.

| Stage / job | What it does | Fails fast on |
|---|---|---|
| **backend-test** | `mvn -B verify` on Java 17 (compiles, runs unit + integration tests against in-memory H2, packages) | any compile/test failure |
| **frontend-test** | `npm ci`, Jest/RTL tests, production build | test or build failure |
| **validate-config** | shellcheck, hadolint, `docker compose config` for both compose files, `promtool check config/rules`, **alert rule unit tests**, dashboard JSON check, gitleaks secret scan | lint errors, invalid configs, committed secrets |
| **docker-build-check** (PRs only) | builds both images without pushing | broken Dockerfile |
| **build-and-push** (main only) | assumes an AWS role via **GitHub OIDC** (no stored keys), builds both images, tags them with the 12-char **commit SHA**, pushes to **Amazon ECR** | build/push failure |
| **deploy** (main only) | uploads the deploy bundle to S3 and runs `scripts/deploy.sh` on the instance through **SSM Run Command**: fetch config from SSM/Secrets Manager, `docker pull`, `compose up -d`, **health gate** (`/healthz` UP incl. DB, `/`, `/api/todos`), **auto-rollback** to the previous tag on failure, then an **external smoke test** against the public URL | non-zero exit of the remote script, failed health check, failed smoke test |

* Jobs are chained with `needs`, so nothing is built or deployed unless tests and validations pass (fail fast).
* **No hardcoded secrets**: only `AWS_ROLE_ARN`, `DEPLOY_BUCKET`, `EC2_INSTANCE_ID`, `APP_URL` are repository secrets; application secrets never pass through CI - the instance reads them from AWS at deploy time.
* **Fully automated**: git push -> running deployment, no approval or manual step (the `production` environment has no required reviewers). `concurrency` prevents overlapping runs on one ref.
* **Rollback workflow**: `.github/workflows/rollback.yml` redeploys any earlier tag in one click.

Required GitHub configuration is listed in [`aws/aws-setup.md`](aws/aws-setup.md#5-provisioning-with-terraform).

## 4. AWS deployment (EC2 + RDS)

Details, security-group table and IAM policies: [`aws/aws-setup.md`](aws/aws-setup.md). Optional IaC: [`aws/iac/`](aws/iac) (Terraform).

* **EC2** (Amazon Linux 2023, Docker + Compose installed by user data) runs the stack from `docker-compose.prod.yml`.
* **RDS MySQL 8.0** in private subnets, `publicly_accessible=false`, encrypted, 7-day backups; its security group accepts 3306 **only from the EC2 security group**.
* **EC2 security group**: 80 open (app), 22 and 3000 (Grafana) restricted to the admin IP; Prometheus is bound to loopback; backend not published.
* **IAM role** on the instance (no AWS keys anywhere): pull from the two ECR repos, read `/todoapp/prod/*` parameters, read the one RDS secret, read deploy bundles from S3, plus SSM core.
* **Credentials outside the code**: RDS master password in Secrets Manager (RDS-generated), Cohere/Slack/Grafana secrets in SSM Parameter Store `SecureString`.

## 5. Monitoring (Prometheus + Grafana)

* `monitoring/prometheus.yml` scrapes the backend (`/actuator/prometheus`), node-exporter (host) and cAdvisor (containers).
* Grafana is provisioned automatically with the Prometheus data source and the dashboard `monitoring/grafana-dashboard.json`:
  request rate, error rate, latency p50/p95/p99, CPU/memory/disk, container restarts and uptime, container CPU/memory, JVM heap, DB connection pool, firing alerts.
* `monitoring/alert-rules.yml` - 8 alerts (backend down, high 5xx rate, DB connection timeouts, container crash loop, high p95 latency, high CPU, low memory, low disk). They appear in Grafana under *Alerting -> Alert rules*. Rationale and what is *not* alerted: [`MONITORING_AND_OPERATIONS.md`](MONITORING_AND_OPERATIONS.md).
* Add a Slack/email contact point in Grafana once (it contains a secret, so it is not in git).

## 6. Failure, rollback and operations docs

* [`FAILURE_AND_ROLLBACK.md`](FAILURE_AND_ROLLBACK.md) - the six required scenarios.
* [`MONITORING_AND_OPERATIONS.md`](MONITORING_AND_OPERATIONS.md) - metrics, logs, alerts, early detection.

## Tests

| Suite | Count | Covers |
|---|---|---|
| `TodoServiceTest` (JUnit + Mockito) | 8 | CRUD service logic, not-found handling, pending query |
| `TodoControllerTest` (`@WebMvcTest`) | 8 | HTTP contract: status codes, JSON, summarize success / Slack failure / Cohere failure / no pending |
| `TodoApiIntegrationTest` (`@SpringBootTest`, H2) | 6 | CRUD lifecycle on a real JPA stack, summarize end-to-end, `/actuator/health` (+ liveness/readiness), `/actuator/prometheus` content, non-exposed actuator endpoints return 404 |
| `TodoSummaryAssistantApplicationTests` | 1 | application context loads (test profile) |
| Frontend Jest/RTL | 18 | API service URLs, form, list, notifications, App flows incl. error paths |
| `promtool test rules` | 7 scenarios | alerts fire when they should and stay quiet when they should not |

```bash
cd Backend/todo-summary-assistant && ./mvnw -B verify          # 23 backend tests (no MySQL needed: H2 test profile)
cd Frontend/todo && CI=true npm test -- --watchAll=false         # 18 frontend tests
docker run --rm --entrypoint promtool -v "$PWD/monitoring:/m:ro" -w /m prom/prometheus:v2.55.1 test rules alert-rules.test.yml
```

## Changes made to application code

Only DevOps-enablement changes; no business logic was altered.

| File | Change |
|---|---|
| `Backend/.../application.properties` | all DB / Cohere / Slack / CORS / port settings now read **environment variables** (the previously committed DB password and placeholders were removed); added Actuator + Prometheus settings, graceful shutdown; `show-sql` off by default |
| `Backend/.../pom.xml` | added `spring-boot-starter-actuator`, `micrometer-registry-prometheus` (metrics endpoint), and test-scope `h2` |
| `Backend/.../config/WebConfig.java` | allowed CORS origin read from `CORS_ALLOWED_ORIGINS` instead of a hard-coded `http://localhost:3000` |
| `Frontend/todo/src/services/todoService.js` | API base from `REACT_APP_API_BASE_URL`, default relative `/api` (was hard-coded `http://localhost:8080`) |
| `Frontend/todo/package.json` | `"proxy": "http://localhost:8080"` for local `npm start` |
| `Backend/.../TodoSummaryAssistantApplicationTests.java` | `@ActiveProfiles("test")` so the context test runs on H2 |
| New test files | see *Tests* |

Pre-existing, intentionally left as is: the `react-hooks/exhaustive-deps` warning in `App.js` (the Docker/CI build runs with `CI=false`; tests are the quality gate), `ddl-auto=update` (production would use Flyway/Liquibase), `MySQL8Dialect` deprecation warning.

## Assumptions

* Region `ap-south-1`; single EC2 instance runs the app and monitoring; `t3.small` recommended (`t3.micro` possible with the provided swap).
* No domain, so HTTP on port 80. HTTPS (ALB + ACM or Caddy) is the first next step.
* RDS is single-AZ to stay small; Multi-AZ is one variable (`db_multi_az`).
* Docker Hub or ECR were both allowed - ECR was chosen so images, pull permissions and the pipeline all use IAM instead of registry passwords.
* Deploys use SSM Run Command (no inbound SSH needed); SSH on 22 is optional and admin-IP-restricted.
* The application starts without Cohere/Slack configured (CRUD works; `/summarize` returns an error until they are set).
* Remember to `terraform destroy` after the review to avoid charges.
