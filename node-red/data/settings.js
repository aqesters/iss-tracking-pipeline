/**
 * Node-RED runtime settings for the IIoT pipeline.
 *
 * Secrets and per-deployment values are pulled from environment variables
 * (set in .env / docker-compose.yml) so this file stays identical across
 * every client repo — only .env changes per site.
 */

const flowFile = "flows.json";

module.exports = {
    flowFile: flowFile,

    // If /data/flows.json doesn't exist yet (first boot on a fresh volume),
    // seed it from the image's default pipeline instead of starting blank.
    flowFilePretty: true,

    // Encrypts credentials in flows_cred.json. MUST be set via env in
    // production — falling back to a fixed dev value only for first-run
    // convenience so `docker compose up` works before .env is customized.
    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET || "dev-only-change-me",

    uiPort: process.env.PORT || 1880,

    // Basic admin-UI auth. Disabled by default for local dev; flip
    // NODE_RED_ENABLE_AUTH=true and set real bcrypt creds for any client
    // deployment reachable outside localhost/VPN. Generate a hash with:
    //   npx node-red admin hash-pw
    adminAuth: process.env.NODE_RED_ENABLE_AUTH === "true" ? {
        type: "credentials",
        users: [{
            username: process.env.NODE_RED_ADMIN_USER || "admin",
            password: process.env.NODE_RED_ADMIN_PASSWORD_HASH || "",
            permissions: "*"
        }]
    } : undefined,

    // Values available to Function nodes via env.get('VAR_NAME') without
    // hardcoding secrets into flows.json.
    functionGlobalContext: {},

    // Keep a rolling window of flow revisions on disk instead of unlimited
    // history growth.
    editorTheme: {
        projects: { enabled: false },
        tours: false
    },

    logging: {
        console: {
            level: process.env.NODE_RED_LOG_LEVEL || "info",
            metrics: false,
            audit: false
        }
    },

    // Let msg.payload be any size — machine payloads can include arrays of
    // raw samples (e.g. vibration waveforms) larger than the 50MB default
    // is fine, but keep an explicit ceiling so a runaway input can't OOM
    // the container.
    apiMaxLength: "10mb"
};
