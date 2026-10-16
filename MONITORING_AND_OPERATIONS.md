# Monitoring and operations (design level)

Stack: Spring Boot Actuator + Micrometer (`/actuator/prometheus`), Prometheus (scrape every 15 s,
7-day retention), node-exporter (host), cAdvisor (containers), Grafana (dashboard
`monitoring/grafana-dashboard.json`, auto-provisioned). Alert rules: `monitoring/alert-rules.yml`,
unit-tested with `promtool test rules monitoring/alert-rules.test.yml`. Grafana lists the rules under
*Alerting -> Alert rules* and the dashboard shows the firing ones. Notification channels (Slack/email
contact points) are configured once in Grafana - they hold secrets, so they are intentionally not in git.

## 1. Which metrics we monitor and why

| Area | Metric (source) | Why it matters |
|---|---|---|
| Availability | `up{job="todo-backend"}` | the single clearest "is it alive" signal |
| Traffic (**R**ate) | `http_server_requests_seconds_count` by status | detects traffic drops (outage upstream) and spikes |
| Errors (**E**rror) | share of 5xx in the above | user-visible failures; the primary SLI |
| Latency (**D**uration) | `histogram_quantile` p50/p95/p99 of `http_server_requests_seconds_bucket` | slowness is an outage users feel first; percentiles, not averages |
| Dependencies | `hikaricp_connections_{active,idle,pending,timeout_total}` | early sign of DB trouble before requests fail |
| JVM | `jvm_memory_used_bytes` vs max (heap) | OOM precursor; leak detection |
| Host saturation | CPU %, memory available %, disk used % on `/` (node-exporter) | the USE method; disk-full and OOM are classic self-inflicted outages |
| Containers | `container_start_time_seconds` (restarts, uptime), per-container CPU/memory (cAdvisor) | crash loops and the noisy neighbour on a shared host |
| Deployment | image tag in `.current_tag`, pipeline status | correlate regressions with releases |

## 2. Which logs are critical

* **Backend container (`docker logs todo-backend`)**: stack traces, `HikariPool` connection errors,
  Hibernate/SQL errors, Cohere/Slack call failures (`Error processing summary`), startup failures.
* **nginx access/error logs (`todo-frontend`)**: 5xx and 499/504 rates, upstream connect failures (backend down).
* **Deployment output**: SSM command output (stored by SSM and printed in the pipeline) - the audit
  trail of what was deployed and whether the health gate/rollback ran.
* **Platform**: RDS events (failover, maintenance, storage), CloudTrail (IAM/SSM/secret access), VPC flow
  logs on rejects if abuse is suspected.
* Logs are JSON-file driver with rotation (10 MB x 3) so they cannot fill the disk. Next step: ship to
  CloudWatch Logs (`awslogs` driver or agent) so they survive instance loss. Secrets are never logged
  (`show-sql` is off by default, actuator exposes only health/info/prometheus).

## 3. Which alerts matter - and which deliberately do not

| Alert | Condition | Severity | Action |
|---|---|---|---|
| `BackendDown` | scrape fails 1 min | critical | page; check container, rollback |
| `HighErrorRate` | 5xx > 5% for 5 min **and** traffic above a floor | critical | page; check logs/DB/Cohere, rollback |
| `DatabaseConnectionTimeouts` | any Hikari timeout in 5 min | critical | check RDS status/SG/credentials |
| `ContainerCrashLoop` | > 2 restarts in 15 min | critical | logs, OOM, rollback |
| `HighLatencyP95` | p95 > 1 s for 10 min (excl. `/summarize`) | warning | investigate slow queries/CPU |
| `HostHighCPU` | > 85% for 10 min | warning | scale up / check credits |
| `HostLowMemory` | < 10% available for 10 min | warning | risk of OOM kills |
| `HostLowDisk` | < 15% free on `/` for 10 min | warning | prune images/logs, grow EBS |

**What we intentionally do not alert on (noise control):**

* Single 5xx on idle traffic - the error-rate rule has a minimum-traffic floor (tested in `alert-rules.test.yml`).
* `/api/todos/summarize` latency - it calls an external LLM + Slack and is legitimately slow; excluded from
  the latency alert (it still shows on the dashboard through the 5xx/error panels).
* 4xx responses - client errors are not service health.
* Short CPU/latency spikes - every threshold has a `for:` window (5-10 min).
* Per-container CPU/memory and JVM heap - dashboard-only; they are causes, the alerts above are symptoms.
* GC pauses, Prometheus/Grafana self-metrics - dashboards only.
* Warnings go to a low-priority channel (Slack); only critical alerts page.

## 4. How operational issues are detected early

1. **Pre-deploy**: the CI gate (unit + integration tests, config linting, promtool rule tests, gitleaks).
2. **At deploy**: health gate with automatic rollback, then an external smoke test of the public URL.
3. **Symptom-based alerts** on errors/latency/availability (what users feel) + **cause-based warnings**
   (disk, memory, CPU, DB timeouts, restarts) that fire *before* the outage.
4. **Trend panels**: disk and memory slopes and heap-vs-max show problems days in advance.
5. **Dead-man's switch** (recommended next step): Prometheus runs on the same host, so a host failure
   silences alerting. Add an external probe (CloudWatch alarm on EC2 `StatusCheckFailed` plus
   an uptime monitor against `http://<EIP>/healthz`) so a total outage still notifies someone.
6. **Runbook links** in alert annotations and the rollback workflow make the first response a one-click action.

## 5. Daily operations cheat sheet

```bash
aws ssm start-session --target <instance-id>          # shell without SSH
docker compose -p todoapp ps                          # state (run from /opt/todoapp, needs exported vars to modify)
docker logs --tail 100 -f todo-backend
curl -s localhost/healthz
cat /opt/todoapp/.current_tag                         # live release
```
