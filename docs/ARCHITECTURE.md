# Architecture

## Data flow

```
[Input node] -> [Math] -> [Stateful Ops] -> [Synthetic] -> [Standardize] -> [InfluxDB out] -> [Grafana]
```

This is the standard ingestion shape used across client deployments (see the
project's "Default data ingestion workflow" doc). Each stage is its own
Node-RED node so it can be inspected, debugged, or swapped independently —
open `node-red/data/flows.json` in the Node-RED editor (`http://localhost:1880`)
to see it wired up.

| Stage | Node | Responsibility |
|---|---|---|
| 1. Input | `Input: Generate Raw Reading` (simulator) | Gets raw data onto the flow. In production this is a protocol node — MQTT in, Modbus Read, OPC-UA Item, S7comm, a REST poll, etc. — not a function node. |
| 2. Math | `Math: Engineering Units` | Converts raw sensor counts to calibrated, human-meaningful units (scaling, offsets, RMS from raw samples). |
| 3. Stateful Ops | `Stateful Ops: Rolling Stats & Run-State` | Anything that needs memory of prior readings: rolling averages, counter deltas, run/idle state detection, uptime timers. Uses Node-RED flow context, not the database, so it's fast and doesn't require a query round-trip per message. |
| 4. Synthetic | `Synthetic: Derived Metrics` | Composite values that don't exist on any single sensor — health score, anomaly score, alert flags. This is where client-specific business logic (OEE, downtime cost, custom KPIs) gets added. |
| 5. Standardize | `Standardize: Prep for InfluxDB` | Shapes the enriched reading into the `[fieldsObject, tagsObject]` point format the `node-red-contrib-influxdb` v2 output node expects (the measurement name itself is set once, on the InfluxDB out node's config, since it's constant for this flow). Centralizing this means every point written to the database has a consistent schema. |
| Sink | `InfluxDB out` | Writes the point to the `machine_metrics` measurement in the configured bucket. |
| Read side | Grafana | Auto-provisioned InfluxDB (Flux) datasource + a starter dashboard querying `machine_metrics`. |

## Why this stage order

Splitting math / stateful ops / synthetic into separate nodes (instead of one
big function) keeps each transformation testable and debuggable in
isolation — you can wire a debug node after any stage while troubleshooting
a client's data without touching the others, and it mirrors how you'd
explain the pipeline to a non-technical stakeholder.

## Going from simulator to a real input

The first two nodes on the canvas (`Simulate sensor tick` and
`Input: Generate Raw Reading`) exist so this repo runs end-to-end with zero
external dependencies — clone it, `docker compose up`, and you have data
flowing into Grafana in under a minute. They are **not** part of the
production pipeline.

To connect a real machine:

1. Delete (or disable) the inject + simulator function node.
2. Add the appropriate input node for the client's equipment:
   - **MQTT** (most common for modern PLCs/gateways, Ignition Edge, etc.): `mqtt in` node (core Node-RED), subscribed to the machine's topic.
   - **Modbus TCP/RTU**: `node-red-contrib-modbus`.
   - **OPC-UA**: `node-red-contrib-opcua` or `node-red-contrib-iiot-opcua`.
   - **Siemens S7**: `node-red-contrib-s7`.
   - **Generic REST poll**: `inject` (timer) -> `http request`.
3. Add a function node right after it that reshapes the raw payload into
   the same fields the `Math` node expects (`machine_id`, `ts`, plus
   whatever raw fields you're scaling). Everything downstream is unchanged.
4. Add the new node's npm package to `node-red/data/package.json` and
   `node-red/Dockerfile`, then rebuild (`docker compose up -d --build`).

## Multi-machine / multi-line scaling

The pipeline is already multi-machine: `machine_id` is a tag on every point,
and the Grafana dashboard has a `machine` template variable that filters by
it. To add more machines, either extend the simulator's `machines` array
(for testing) or just point more input nodes at the same downstream chain —
tag each with its own `machine_id` in the input-reshaping function.

If a client has more than ~500 distinct tag combinations written at high
frequency, InfluxDB's cardinality limits become a real concern — see the
note in the project's "Core tool stack" doc about swapping to TimescaleDB
for that case.

## Where client-specific logic goes

- Calibration constants -> `Math` node.
- Thresholds (vibration cutoff for run/idle, rolling window size) -> `Stateful Ops` node.
- KPI formulas (health score weighting, alert conditions, OEE) -> `Synthetic` node.
- New measurements/tags -> `Standardize` node.

Keeping these edits inside their designated node (rather than scattered
across the flow) is what makes diffs between client repos easy to review
when you're reusing this template.
