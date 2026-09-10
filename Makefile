.PHONY: up down restart logs ps config backup restore clean secrets sync-flows restore-flows

# Re-evaluated every time it's referenced (not cached at parse time),
# so it's always current even mid-chain, e.g. `make up sync-flows`
NODE_RED_CONTAINER = $(shell docker compose ps -q node-red)
INFLUX_CONTAINER = $(shell docker compose ps -q influxdb)

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

# Copy NODE-RED flows and settings from container storage to local git repo
sync-flows:
	@test -n "$(NODE_RED_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	docker cp $(NODE_RED_CONTAINER):/data/flows.json ./node-red/data/flows.json
	docker cp $(NODE_RED_CONTAINER):/data/settings.js ./node-red/data/settings.js
	@echo "Synced flows.json and settings.js from container to repo"

# Copy NODE-RED flows and settings from local git repo to container storage
restore-flows:
	@test -n "$(NODE_RED_CONTAINER)" || (echo "Container not running — run 'make up' first" && exit 1)
	docker cp ./node-red/data/flows.json $(NODE_RED_CONTAINER):/data/flows.json
	docker cp ./node-red/data/settings.js $(NODE_RED_CONTAINER):/data/settings.js
	@echo "Restored flows.json and settings.js from repo to container — redeploy in the editor to apply"

# DANGER: removes containers AND volumes (all InfluxDB/Grafana/Node-RED data)
#clean:
#	docker compose down -v