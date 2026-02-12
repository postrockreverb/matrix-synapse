# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Compose deployment configuration for a self-hosted Matrix Synapse homeserver. This is **not** a software library — it's infrastructure-as-code with no build step, test suite, or linting.

## Commands

```bash
# Start/stop all services
docker compose up -d
docker compose down

# View logs
docker compose logs -f [synapse|caddy|postgres|element|coturn]

# Update images
docker compose pull && docker compose up -d

# Create admin user
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml -u admin -a http://localhost:8008

# Backup/restore database
docker compose exec postgres pg_dump -U synapse synapse > backup.sql
cat backup.sql | docker compose exec -T postgres psql -U synapse synapse
```

## Architecture

```
Internet
  ├─ :80/:443/:8448 ──► Caddy (TLS termination, auto Let's Encrypt)
  │                        ├─► Synapse (:8008) ──► PostgreSQL
  │                        ├─► Element Web (:80)
  │                        ├─► lk-jwt-service (:8080)  [livekit subdomain]
  │                        └─► LiveKit (:7880)          [livekit subdomain WebSocket]
  ├─ :3478/:5349/:49152-49200 ──► coturn (host network, TURN/STUN)
  ├─ :7881/tcp ──► LiveKit (WebRTC TCP fallback)
  └─ :50000-50200/udp ──► LiveKit (WebRTC media)
```

**Networks**: `matrix_internal` (Synapse ↔ PostgreSQL only), `caddy_net` (Caddy ↔ Synapse/Element/LiveKit/lk-jwt-service). coturn uses host networking to avoid per-port iptables rules for the relay range.

## Configuration

Each config has an `.example` file that gets copied and edited. Replace `CHANGEME_*` values with your own:

| Example File | Copy To | Purpose |
|-------------|---------|---------|
| `synapse/homeserver.yaml.example` | `synapse/homeserver.yaml` | Synapse server config (domain, secrets, database, TURN) |
| `coturn/turnserver.conf.example` | `coturn/turnserver.conf` | TURN/STUN server (shared secret, external IP) |
| `element/config.json.example` | `element/config.json` | Element web client (homeserver URL, domain) |
| `livekit/config.yaml.example` | `livekit/config.yaml` | LiveKit SFU (API keys, TURN, ports) |
| `synapse/log.config` | *(used directly)* | Synapse logging (no user edits needed) |

The copied config files are gitignored since they contain secrets. The `.example` files are committed.

**`.env`** holds runtime vars consumed by Docker Compose: `SYNAPSE_HOSTNAME`, `ELEMENT_HOSTNAME`, `LIVEKIT_HOSTNAME` (used by Caddy), `DOMAIN` (used by lk-jwt-service), `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` (used by lk-jwt-service), `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` (used by PostgreSQL).

## Key Constraints

- YAML in `homeserver.yaml` is whitespace-sensitive — preserve indentation exactly
- The Caddy `Caddyfile` uses `{$ENV_VAR}` syntax for runtime environment variable substitution
- Federation requires `.well-known` delegation if Matrix IDs use the base domain rather than the `matrix.` subdomain — see `caddy/Caddyfile` comments or README for setup options
- The `turn_shared_secret` in `homeserver.yaml` must match `static-auth-secret` in `turnserver.conf`
- LiveKit API key/secret must match between `.env` and `livekit/config.yaml`
- The TURN secret in `livekit/config.yaml` must also match `turnserver.conf`
