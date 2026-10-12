# ISS Tracking Pipeline

Dockerized Node-RED → InfluxDB → Grafana stack that polls public ISS APIs, stores the results as time series, and displays them on a Grafana dashboard.

| Component | Role |
|---|---|
| [Node-RED](https://nodered.org/) | Polls the ISS APIs, reshapes the JSON, writes to InfluxDB |
| [InfluxDB 2.x](https://www.influxdata.com/) | Time-series storage (org `iss_data`, bucket `iss_position_data`) |
| [Grafana 13](https://grafana.com/) | ISS Tracking dashboard |
| Docker Compose | Reproducible deployment (project name `iss-tracker`) |
| [gcx](https://github.com/grafana/gcx) | Syncs Grafana dashboards to and from this repo |

## Data flows

| Flow | Source | Poll interval | Measurement | Fields |
|---|---|---|---|---|
| A (optional) | `api.open-notify.org/iss-now.json` | 10 s | `iss_position` | `latitude`, `longitude` |
| B (primary) | `api.wheretheiss.at/v1/satellites/25544` | 5–10 s | `iss_track` | `latitude`, `longitude`, `altitude_km`, `velocity_kmh`, `footprint_km`, `solar_lat`, `solar_lon` (tag: `visibility`) |
| C | `api.open-notify.org/astros.json` | 1 h | `iss_crew` | `crew_count`, `total_people_in_space` |

All three write to the `iss_position_data` bucket. Flow B covers everything Flow A does, so Flow A can stay disabled.

The host needs outbound HTTP/HTTPS access to both APIs. Check before setup:

```bash
curl https://api.wheretheiss.at/v1/satellites/25544
curl http://api.open-notify.org/astros.json
```

---

## First-time setup

Requires Docker and Docker Compose on the host. The InfluxDB image in `docker-compose.yml` must stay pinned to a 2.x tag (e.g. `influxdb:2.7`). The `latest` tag now points to InfluxDB 3, which doesn't support Flux.

### 1. Create `.env`

```bash
cp .env.example .env
make secrets    # prints random values to paste into .env
```

The command `make secrets` will create random values. Copy these into the `.env` file.

- `INFLUXDB_INIT_ADMIN_TOKEN` and `INFLUXDB_TOKEN`: use the same value for both. This is the only InfluxDB token in the stack. Node-RED and Grafana both connect with it.
- `NODE_RED_CREDENTIAL_SECRET`: random string that encrypts credentials Node-RED stores. Changing it after first run invalidates saved node credentials.



Leave the following values at their defaults unless you have a reason to change them. Each `INIT_*` value must match its counterpart:

| Variable | Default |
|---|---|
| `INFLUXDB_INIT_ORG` / `INFLUXDB_ORG` | `iss_data` |
| `INFLUXDB_INIT_BUCKET` / `INFLUXDB_BUCKET` | `iss_position_data` |
| `INFLUXDB_INIT_RETENTION` | `90d` |
| `INFLUXDB_URL` | `http://influxdb:8086` (internal Docker network) |
| `NODE_RED_PORT` / `GRAFANA_PORT` | `1880` / `3000` |

`GRAFANA_SA_TOKEN` stays a placeholder for now. You fill it in after Grafana is running (step 4).

`.env` is gitignored. Never commit it.

### 2. Start the stack

```bash
make up
```

| Service | URL |
|---|---|
| Node-RED | `http://localhost:1880` |
| Grafana | `http://localhost:3000` [user: admin / password: default-password] |
| InfluxDB | `http://localhost:8086` [user: admin / password: default-password] |

On first boot, InfluxDB creates the `iss_data` org and the `iss_position_data` bucket from `.env`.

### 3. Load the flows and add the token in Node-RED

In the Node-RED editor:

1. Double-click the **influxdb out** node, then click the pencil icon next to **Server** to edit the shared config node.
2. Paste the `INFLUXDB_TOKEN` value from `.env` into **Token** and confirm **Organization** is `iss_data`.
3. Click **Update**, **Done**, then **Deploy**.

Node-RED stores this token in `flows_cred.json`, which never syncs to git. Re-enter it on every new deployment.

### 4. Set up Grafana syncing and restore the dashboards

Run the following command to create the ISS Tracking dashboard:

```bash
make restore-grafana
```

Grafana's InfluxDB data source is provisioned automatically from `grafana/provisioning/datasources/influxdb.yml`, using `INFLUXDB_TOKEN` and the other values in `.env`. To save any dashboard changes to the repo, follow instructions in [Grafana setup for syncing](#grafana-setup-for-syncing).

### 5. Verify

1. Node-RED debug sidebar (bug icon): no errors after a few poll cycles.
2. InfluxDB **Data Explorer**: bucket `iss_position_data` shows recent points under `iss_track` and `iss_crew`.
3. Grafana: the **ISS Tracking** dashboard shows the map, longitude and latitude, and updates on refresh.

---

## Making changes

Each service keeps its live state in a Docker volume, not in this repo. Edit in the UI, then run `make sync` to copy the current state into the repo, and commit.
**To sync Grafana dashboards changes, you must first complete instructions for [Grafana setup for syncing](#grafana-setup-for-syncing).**

```bash
# 1. Edit in Node-RED (then Deploy), Grafana (then Save dashboard), or InfluxDB
# 2. Copy the live state into the repo
make sync
# 3. Review and commit
git add -A
git commit -m "Describe the change"
```

`make sync` runs three targets, which you can also run on their own:

| Target | What it captures | Where it goes |
|---|---|---|
| `make sync-flows` | Node-RED `flows.json` and `settings.js` | `node-red/data/` |
| `make sync-grafana` | All Grafana dashboards and folders | `grafana/resources/` |
| `make sync-influx` | InfluxDB buckets, tasks, and other resources as a template (no data, no tokens) | `influxdb/template.yml` |

Don't edit files in the repo and expect them to take effect. The `restore-*` targets are the only way to push repo files into the running services.

### Grafana setup for syncing

`sync-grafana` and `restore-grafana` use gcx, which runs on the machine where you run `make` and talks to Grafana over its API. Set this up once per machine.

1. **Install gcx**
   ```bash
   brew install gcx
   # or: curl -fsSL https://raw.githubusercontent.com/grafana/gcx/main/scripts/install.sh | sh
   gcx --version
   ```
2. **Create a service account** in Grafana: **Administration → Users and access → Service accounts → Add service account**. Name it `gcx-sync` and set the role to **Admin**.
3. **Generate a token**: on the service account's page, **Add service account token → Generate token**. Copy it right away. Tokens start with `glsa_`.
4. **Save the token** as `GRAFANA_SA_TOKEN` in `.env`.
5. **Log in gcx**
   ```bash
   gcx login local --server http://<host>:3000 --token <glsa token here> --yes
   gcx config check
   ```
   The server must be the same address you use for Grafana in your browser.

**Data sources:** only dashboards and folders are synced. Data sources come from `grafana/provisioning/datasources/`. A data source added through the Grafana UI is not captured by `make sync`, so add it to the provisioning folder if it needs to survive a rebuild.

### Node-RED notes

`node-red/data/` is not bind-mounted. Node-RED's runtime state lives in the `node-red-data` named volume. A bind mount caused `EBUSY` errors on deploy (macOS Spotlight interfering with Node-RED's atomic rename-on-save), so `sync-flows` and `restore-flows` bridge the volume to git deliberately with `docker cp`.

After `make restore-flows`, open the editor and click **Deploy** so Node-RED loads the restored flows.

If the Node-RED editor is reachable outside your LAN or VPN, configure `adminAuth` in `settings.js`, set `NODE_RED_ENABLE_AUTH=true` in `.env`, then run `make sync-flows`.

### InfluxDB notes

`sync-influx` and `restore-influx` read the org name from `INFLUX_ORG` in the Makefile. Keep it set to `iss_data`, matching `INFLUXDB_ORG` in `.env`.

`restore-influx` (`influx apply`) is meant for a fresh instance. Against an instance that already has these resources, such as the `iss_position_data` bucket created on first boot, it can fail on name conflicts or create duplicates.

Time-series data is not in git. Back it up with `make backup-influx` (writes to `./backups/`, which is gitignored).

---

## Command reference

```bash
make up               # start the stack
make down             # stop the stack (data persists in named volumes)
make ps               # container status
make logs             # tail all container logs
make config           # validate docker-compose.yml + .env interpolation
make secrets          # print random values for .env

make sync             # sync-flows + sync-grafana + sync-influx
make restore          # restore-flows + restore-grafana + restore-influx

make sync-flows       # Node-RED flows/settings: container → repo
make restore-flows    # Node-RED flows/settings: repo → container (then Deploy)
make sync-grafana     # Grafana dashboards/folders: Grafana → repo (gcx pull)
make restore-grafana  # Grafana dashboards/folders: repo → Grafana (gcx push)
make sync-influx      # InfluxDB resource template: container → repo
make restore-influx   # InfluxDB resource template: repo → container (fresh instance only)

make backup           # dump InfluxDB data + Node-RED flows/creds to ./backups/<timestamp>/
make backup-influx    # InfluxDB data only, to ./backups/influx-<timestamp>/
make clean            # stop the stack AND delete all volumes (destructive)
```

## Repo layout

```
.
├── docker-compose.yml
├── docker-compose.portainer.yml       # optional Docker GUI (see file header)
├── .env.example                       # copy to .env and fill in secrets
├── Makefile
├── node-red/
│   ├── Dockerfile                     # bakes in node-red-contrib-influxdb
│   └── data/
│       ├── flows.json                 # ISS flows (make sync-flows)
│       ├── settings.js                # runtime config, no hardcoded secrets
│       └── package.json               # palette manifest
├── influxdb/
│   └── template.yml                   # bucket/task definitions (make sync-influx)
└── grafana/
    ├── provisioning/
    │   └── datasources/influxdb.yml   # auto-configures the InfluxDB data source
    └── resources/                     # dashboards + folders (make sync-grafana)
        ├── dashboards.v0alpha1.dashboard.grafana.app/<uid>.json
        └── folders.*/<uid>.json
```

gcx names subfolders after Grafana's API type and version (e.g. `v0alpha1`). The dashboard JSON inside may use a newer schema such as `dashboard.grafana.app/v2`. That's expected, and `restore-grafana` pushes each file in its own format.

## Secrets

Keep these out of every commit (covered by `.gitignore`):

- `.env`: InfluxDB admin token, Grafana admin password, Grafana service account token, Node-RED credential secret.
- `node-red/data/flows_cred.json`: lives only in the Node-RED volume. `make backup` captures an encrypted copy outside git.
- `backups/`: InfluxDB data backups.

gcx also keeps its own copy of the service account token in `~/.config/gcx/config.yaml` on your machine.

## Notes

- **Why Flux:** the Grafana data source is provisioned in Flux mode to match InfluxDB 2.x's native query language. In Flux, the bucket is set in each query (`from(bucket: "iss_position_data")`), not by the data source's default bucket.
- **Environment variables:** Node-RED (`${VAR}` in `flows.json`) and Grafana (`$__env{VAR}` in provisioning YAML) read values from the container environment at startup. Change `.env` and restart the affected container to apply.
- **Anonymous Grafana access:** `GRAFANA_ALLOW_ANONYMOUS=true` lets anyone on the network view dashboards without logging in, which is handy for a wall display. Leave it `false` otherwise.
- **Single InfluxDB token:** Node-RED and Grafana share the admin token (`INFLUXDB_TOKEN`). It has full access to the InfluxDB instance, so treat `.env` accordingly.