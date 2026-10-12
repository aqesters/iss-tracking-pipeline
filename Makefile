.PHONY: up down restart logs ps config backup restore clean secrets sync-flows restore-flows

-include .env
export

# Re-evaluated every time it's referenced (not cached at parse time),
# so it's always current even mid-chain (e.g. after a `make up`).
NODE_RED_CONTAINER = $(shell docker compose ps -q node-red)
INFLUXDB_CONTAINER = $(shell docker compose ps -q influxdb)
INFLUX_ORG ?= $(INFLUXDB_INIT_ORG)
STAMP      := $(shell date +%Y%m%d-%H%M%S)

# Bring the stack up (build Node-RED image if needed)
up:
	docker compose up -d --build
down:
	docker compose down
restart:
	docker compose restart
logs:
	docker compose logs -f --tail=200
ps:
	docker compose ps

# DANGER: removes containers AND volumes (all InfluxDB/Grafana/Node-RED data)
#clean:
#	docker compose down -v

# Validate compose file + interpolated env without starting anything
config:
	docker compose config

# Dump InfluxDB data + Node-RED flows to ./backups/<timestamp>/
backup:
	@test -n "$(NODE_RED_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	@test -n "$(INFLUX_CONTAINER)" || (echo "InfluxDB container not running — run 'make up' first" && exit 1)
	@mkdir -p backups/$$(date +%Y%m%d-%H%M%S)
	@BK=backups/$$(date +%Y%m%d-%H%M%S); \
	docker compose exec -T influxdb influx backup /tmp/backup --org "$${INFLUXDB_ORG}" && \
	docker cp $(INFLUX_CONTAINER):/tmp/backup "$$BK/influxdb" && \
	docker cp $(NODE_RED_CONTAINER):/data/flows.json "$$BK/flows.json" && \
	docker cp $(NODE_RED_CONTAINER):/data/flows_cred.json "$$BK/flows_cred.json" && \
	echo "Backup written to $$BK"

# Generate fresh random secrets for .env (prints to stdout — paste manually)
secrets:
	@echo "INFLUXDB_INIT_ADMIN_TOKEN=$$(openssl rand -hex 32)"
	@echo "INFLUXDB_TOKEN=<same value as above>"
	@echo "NODE_RED_CREDENTIAL_SECRET=$$(openssl rand -hex 32)"
	@echo "INFLUXDB_INIT_PASSWORD=$$(openssl rand -base64 18)"
	@echo "GRAFANA_ADMIN_PASSWORD=$$(openssl rand -base64 18)"

# ---------- Node-RED ----------

# Copy Node-RED flows and settings from container storage to local git repo
sync-flows:
	@test -n "$(NODE_RED_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	docker cp $(NODE_RED_CONTAINER):/data/flows.json ./node-red/data/flows.json
	docker cp $(NODE_RED_CONTAINER):/data/settings.js ./node-red/data/settings.js
	@echo "Synced flows.json and settings.js from container to repo\n"

# Copy Node-RED flows and settings from local git repo to container storage
restore-flows:
	@test -n "$(NODE_RED_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	docker cp ./node-red/data/flows.json $(NODE_RED_CONTAINER):/data/flows.json
	docker cp ./node-red/data/settings.js $(NODE_RED_CONTAINER):/data/settings.js
	@echo "Restored flows.json and settings.js from repo to container — redeploy in the editor to apply\n"

# ---------- Grafana ----------

# Pull all dashboards from Grafana into the repo
sync-grafana:
	@command -v gcx >/dev/null || (echo "gcx not installed — see https://github.com/grafana/gcx#installation" && exit 1)
	@mkdir -p ./grafana/dashboards
	gcx resources pull dashboards -p ./grafana/dashboards
	@echo "Synced Grafana dashboards from container to repo\n"

# Push dashboards from the repo back into Grafana
restore-grafana:
	@command -v gcx >/dev/null || (echo "gcx not installed — see https://github.com/grafana/gcx#installation" && exit 1)
	gcx resources push -p ./grafana/dashboards
	@echo "Restored Grafana dashboards from repo to container\n"

# ---------- InfluxDB ----------

# Export buckets, tasks, dashboards, etc. as a template (no data, no tokens)
sync-influx:
	@test -n "$(INFLUXDB_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	@mkdir -p ./influxdb
	docker exec $(INFLUXDB_CONTAINER) influx export all --org $(INFLUX_ORG) --file /tmp/influx-template.yml
	docker cp $(INFLUXDB_CONTAINER):/tmp/influx-template.yml ./influxdb/template.yml
	docker exec $(INFLUXDB_CONTAINER) rm -f /tmp/influx-template.yml
	@echo "Synced InfluxDB resource template from container to repo\n"

# Recreate buckets, tasks, etc. from the template (intended for a fresh instance)
restore-influx:
	@test -n "$(INFLUXDB_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	docker cp ./influxdb/template.yml $(INFLUXDB_CONTAINER):/tmp/influx-template.yml
	docker exec $(INFLUXDB_CONTAINER) influx apply --org $(INFLUX_ORG) --file /tmp/influx-template.yml --force yes
	docker exec $(INFLUXDB_CONTAINER) rm -f /tmp/influx-template.yml
	@echo "Restored InfluxDB resources from repo to container\n"

# Back up time-series data to ./backups (gitignored, not part of the repo)
backup-influx:
	@test -n "$(INFLUXDB_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	@mkdir -p ./backups
	docker exec $(INFLUXDB_CONTAINER) influx backup /tmp/influx-backup
	docker cp $(INFLUXDB_CONTAINER):/tmp/influx-backup ./backups/influx-$(STAMP)
	docker exec $(INFLUXDB_CONTAINER) rm -rf /tmp/influx-backup
	@echo "Backed up InfluxDB data to ./backups/influx-$(STAMP)"

# ---------- All ----------

sync: sync-flows sync-grafana sync-influx
restore: restore-flows restore-grafana restore-influx