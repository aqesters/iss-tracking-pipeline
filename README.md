# IIoT Data Pipeline Template

Dockerized Node-RED -> InfluxDB -> Grafana stack for pulling machine/process
data off the plant floor and into dashboards clients can actually use.

This is a **template repo** — clone it per client (`git clone` into a new
private repo, or use it as a GitHub template), customize the input node and
the business logic in `node-red/data/flows.json`, and ship it. See
`docs/ARCHITECTURE.md` for how the pipeline is structured and
`docs/ARCHITECTURE.md#going-from-simulator-to-a-real-input` for wiring up a
client's actual equipment.

## Stack

| Component | Role |
|---|---|
| [Node-RED](https://nodered.org/) | Ingestion, routing, and transformation |
| [InfluxDB 2.x](https://www.influxdata.com/) | Time-series storage |
| [Grafana](https://grafana.com/) | Dashboards |
| Docker Compose | Reproducible deployment |

Runs out of the box with a built-in data simulator (three fake machines) so
you can see the whole pipeline working before connecting real hardware.

## Quick start

Requires Docker and Docker Compose.

```bash
cp .env.example .env
```

Generate real secrets instead of the placeholders (prints values to paste into `.env`):

```bash
make secrets
```

At minimum, set in `.env`:
- `INFLUXDB_INIT_ADMIN_TOKEN` and `INFLUXDB_TOKEN` — **use the same value for both.** The former is what InfluxDB creates itself with on first boot; the latter is what Node-RED/Grafana authenticate with.
- `INFLUXDB_INIT_PASSWORD`, `GRAFANA_ADMIN_PASSWORD` — real passwords.
- `NODE_RED_CREDENTIAL_SECRET` — random string, used to encrypt any credentials Node-RED stores.
- `INFLUXDB_INIT_ORG` / `INFLUXDB_ORG` and `INFLUXDB_INIT_BUCKET` / `INFLUXDB_BUCKET` — keep each pair identical; rename to match the client.

Then bring up the stack:

```bash
make up
# or: docker compose up -d --build
```

Open:
- Node-RED editor: http://localhost:1880
- Grafana: http://localhost:3000 (login with `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`)
- InfluxDB UI: http://localhost:8086 (only if you keep the port binding in `docker-compose.yml`)

The **Plant Floor Overview** dashboard in Grafana should show data moving
within ~10 seconds — the simulator injects a reading every 3 seconds for one
of three fake machines (`press-01`, `press-02`, `cnc-04`).

## Repo layout

```
.
├── docker-compose.yml              # Core 3-service stack
├── docker-compose.portainer.yml    # Optional: add a Docker GUI (see file header)
├── .env.example                    # Copy to .env, fill in secrets
├── Makefile                        # up / down / logs / backup / secrets / sync-flows / restore-flows
├── node-red/
│   ├── Dockerfile                  # Bakes in node-red-contrib-influxdb at build time
│   └── data/
│       ├── flows.json              # Repo copy of the pipeline — see "Saving your work" below
│       ├── settings.js             # Repo copy of runtime config (no secrets hardcoded)
│       └── package.json            # Palette manifest
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/influxdb.yml    # Auto-configures the InfluxDB datasource
│   │   └── dashboards/dashboard.yml    # Auto-loads dashboards from grafana/dashboards/
│   └── dashboards/
│       └── plant-floor-overview.json   # Starter dashboard
└── docs/
    └── ARCHITECTURE.md             # Pipeline design + how to connect real equipment
```

**Note on `node-red/data/`:** these files are *not* bind-mounted into the
running container. Node-RED's actual runtime state (`flows.json`,
`settings.js`, `flows_cred.json`, `node_modules`, etc.) lives in a Docker
named volume (`node-red-data`), independent of this folder. The copies in
`node-red/data/` are what you see in git — they only reflect the live state
after you explicitly run `make sync-flows` (see below). A named volume was
chosen over a bind mount after hitting host-filesystem issues (notably
Docker Desktop on macOS interfering with Node-RED's atomic file rename on
deploy) that don't reproduce with this approach.

## Common tasks

```bash
make logs           # tail all container logs
make ps              # container status
make config          # validate docker-compose.yml + .env interpolation
make backup          # dump InfluxDB data + Node-RED flows/creds to ./backups/<timestamp>/
make sync-flows      # pull flows.json + settings.js from the running container into the repo
make restore-flows   # push the repo's flows.json + settings.js into the running container
make down            # stop the stack (keeps data — named volume persists)
make clean           # stop the stack AND delete all volumes (destructive, commented out by default)
```

## Saving your work: flows.json and settings.js

Node-RED writes directly to the named volume, not to this repo folder. To
get your changes into git, or to load a client's version onto a fresh
machine, use the sync/restore commands rather than editing the files under
`node-red/data/` directly and expecting them to take effect.

**While actively developing (editor → repo):**
```bash
# 1. Edit flows in the Node-RED UI as normal (http://localhost:1880), hit Deploy
# 2. Pull the current state out of the container and into the repo
make sync-flows
# 3. Review and commit
git add node-red/data/flows.json node-red/data/settings.js
git commit -m "Update pipeline logic for <change>"
```

**On a fresh clone or a new machine (repo → editor):**
```bash
make up              # creates the volume + starts the containers
make restore-flows   # pushes the repo's flows.json + settings.js into the container
# Then open the Node-RED editor and hit Deploy so Node-RED picks up the change
```

Both `sync-flows` and `restore-flows` require the stack to already be
running (`make up`) — they operate via `docker cp` against the live
container, not the volume directly.

**`flows_cred.json` is intentionally excluded from this workflow.** It never
syncs to the repo and is not tracked in git. It lives only in the named
volume, decrypted using `NODE_RED_CREDENTIAL_SECRET` from `.env`. Re-enter
credentials (PLC auth, tokens, etc.) through the Node-RED editor on each new
deployment. If you need a recovery copy, `make backup` captures it as part
of the encrypted-at-rest backup — outside of git entirely.

## Version control per client

Per the standard workflow: **one private repo per client.**

```bash
# Starting a new client from this template
git clone <this-repo-url> client-acme-pipeline
cd client-acme-pipeline
rm -rf .git && git init
git remote add origin <new-private-repo-url>
cp .env.example .env   # fill in this client's real secrets — .env is gitignored
make up
make restore-flows     # load the template's starter flows.json/settings.js into the new container
git add .
git commit -m "Initial pipeline for Acme Manufacturing"
git push -u origin main
```

Keep `.env` and `node-red/data/flows_cred.json` out of every commit (already
covered by `.gitignore`) — they hold the InfluxDB token, Grafana admin
password, and any credentials Node-RED encrypts.

## Going live at a client site

1. Replace the simulator with a real input node for their equipment (MQTT / Modbus / OPC-UA / S7 / REST) — see `docs/ARCHITECTURE.md`.
2. Tune calibration constants, thresholds, and health-score weighting in the `Math`, `Stateful Ops`, and `Synthetic` function nodes for their actual machines, then `make sync-flows` and commit.
3. Set `NODE_RED_ENABLE_AUTH=true` and configure `adminAuth` in `node-red/data/settings.js` if the Node-RED editor is reachable outside a VPN/Tailscale network — edit via the Node-RED UI or a direct volume edit, then `make sync-flows` to capture it in git.
4. Turn off the public InfluxDB port binding in `docker-compose.yml` (leave InfluxDB reachable only on the internal Docker network) once you don't need it for debugging.
5. Decide on hosting (client-hosted vs. your managed VM vs. hybrid) and remote access (Tailscale vs. WireGuard) per the standard tool-stack decision tree.
6. Point Uptime Kuma (run centrally, across all clients) at this stack's exposed endpoints.
7. Set a real retention policy (`INFLUXDB_INIT_RETENTION`) matching what the client needs and what your storage budget allows.

## Notes

- **Why Flux, not InfluxQL**: the Grafana datasource is provisioned in Flux mode to match InfluxDB 2.x's native query language and to use `schema.tagValues()` for the machine-picker dashboard variable. If you're more comfortable in InfluxQL, InfluxDB 2.x still accepts it via the `/query` compatibility endpoint, but the provisioned datasource here is Flux-first.
- **Environment variable substitution**: both Node-RED (`${VAR}` in `flows.json`) and Grafana (`$__env{VAR}` in provisioning YAML) resolve these directly from the container's environment at startup — nothing needs templating at build time. Update `.env` and restart the affected container to change them.
- **Why a named volume instead of a bind mount for `node-red/data/`**: bind-mounting `flows.json` directly triggered `EBUSY: resource busy or locked` errors on deploy, traced to macOS Spotlight indexing interfering with Node-RED's atomic rename-on-save. The named volume sidesteps this entirely; `make sync-flows` / `make restore-flows` bridge it back to git deliberately rather than automatically.

## To Do List

- Create separate InfluxDB tokens for write-only access (for Node-RED) and read-only access (for Grafana)
