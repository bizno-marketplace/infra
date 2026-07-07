# Observability — Local Setup (Docker Compose)

Stack: **Prometheus** (metrics) + **Grafana** (dashboards).

**A single config supports both modes** — run the services via IDE, via
Docker, or mixed (some in the IDE, others in Docker), without editing
anything. Each Prometheus job has two targets (container name +
`host.docker.internal`); whichever one isn't active simply shows up as
`DOWN`, which is expected.

## Structure

```
docker-compose.observability.yml
observability/
  prometheus/
    prometheus.yml              # scrape config (2 targets per service)
  grafana/
    provisioning/
      datasources/
        prometheus.yml          # auto-provisioned datasource
      dashboards/
        dashboards.yml          # dashboard provider
        json/                   # (to be created) dashboard .json files go here
```

## Pinned versions

Docker images are pinned to specific stable versions — **never use `:latest`**,
to avoid a `docker compose pull` silently bringing in a new version with
breaking changes:

- Prometheus: `v3.12.0`
- Grafana: `13.1.0`

To upgrade in the future: check the changelog of the new version first
(https://github.com/prometheus/prometheus/releases and https://github.com/grafana/grafana/releases),
test locally, and only then bump the tag explicitly in this file (in its own
PR, not mixed with other changes).

## Management ports (convention: main port + 1000)

| Service          | Main port | Management port |
|------------------|-----------|------------------|
| api-gateway      | 8080      | 9080             |
| auth-service     | 8081      | 9081             |
| discovery-server | 8761      | 9761             |
| config-server    | 8888      | 9888             |

Configured:
- `api-gateway` and `auth-service`: via `bizno-configs` (service-specific
  override files `api-gateway/application.yml` and `auth-service/application.yml`).
- `discovery-server` and `config-server`: locally, in each repo's own
  `application.yml`.

## Initial setup (one-time)

1. **Create the shared network** (only used when services run in Docker;
   doesn't get in the way of IDE mode):

   ```bash
   docker network create bizno-net
   ```

2. **In your main `docker-compose`**, make sure the 4 services join this
   same external `bizno-net` network, with these exact service names:
   `auth-service`, `api-gateway`, `discovery-server`, `config-server`.

   ```yaml
   # in your main docker-compose, for each service:
   networks:
     - bizno-net

   networks:
     bizno-net:
       external: true
   ```

## Day-to-day usage

There are no mode-specific steps — always bring up the observability stack
the same way:

```bash
docker compose -f docker-compose.observability.yml up -d
```

Then run the 4 services however you want that day — all in the IDE, all in
Docker, or mixed. Nothing in the config changes.

## Validating the scrape

Open `http://localhost:9090/targets`. For each service you'll see **two
targets** (`source="docker"` and `source="ide"`) — whichever is active
shows `UP`, the other `DOWN`. This is expected, not an error.

If both targets for a service show `DOWN`:
- confirm the service is actually running
- confirm the management port (table above) and that
  `/actuator/prometheus` is exposed
- if it's the `docker` target that's failing: confirm the container is on
  the `bizno-net` network
- if it's the `ide` target that's failing, on Linux: confirm
  `extra_hosts: host.docker.internal:host-gateway` is present in
  `docker-compose.observability.yml`

## Note on Grafana dashboards

Since each service has two targets, a metric like `up` will have two series
per service (`source="docker"` and `source="ide"`). When building dashboards,
aggregate by `service` (e.g. `max by (service) (...)`) so you don't have to
worry about which of the two is active — business metrics
(`auth.seller.registered`, etc.) don't have this issue, since they only
exist on whichever target is actually running.

## Next step

Once the scrape is confirmed, we'll create dashboards (`.json`) for the
business metrics (`auth.seller.registered`, `auth.seller.approved`,
`auth.seller.rejected`, `auth.seller.resubmitted`, `auth.buyer.registered`,
`auth.grpc.validate_token.duration`) and place them in
`observability/grafana/provisioning/dashboards/json/`.