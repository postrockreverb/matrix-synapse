# Matrix Synapse - Docker Compose Deployment

A declarative, repeatable Matrix Synapse deployment with Docker Compose. Includes everything needed for a fully-featured Matrix homeserver with VoIP, screen sharing, and federation.

## What's Included

| Service | Purpose |
|---------|---------|
| **Synapse** | Matrix homeserver |
| **PostgreSQL 16** | Database backend (not SQLite) |
| **Element Web** | Matrix web client |
| **coturn** | TURN/STUN server for VoIP and screen sharing |
| **LiveKit** | SFU for Element Call group voice/video (MatrixRTC) |
| **lk-jwt-service** | Token service that authorizes Matrix users for LiveKit |

## Architecture

```
Internet
  ├─ :80/:443/:8448 ──► Nginx Proxy Manager (TLS termination, external)
  │                        ├─► Synapse (:8008) ──► PostgreSQL
  │                        ├─► Element Web (:80)
  │                        ├─► lk-jwt-service (:8080)  [livekit.example.com]
  │                        └─► LiveKit (:7880)          [livekit.example.com WebSocket]
  ├─ :3478/:5349/:49152-49200 ──► coturn (host network, TURN/STUN)
  ├─ :7881/tcp ──► LiveKit (WebRTC TCP fallback)
  └─ :50000-50200/udp ──► LiveKit (WebRTC media)
```

## Quick Start

```bash
# 1. Clone and enter the directory
git clone <this-repo> && cd matrix-synapse-docker

# 2. Run the interactive configuration script
#    (copies .example files, prompts for values, generates secrets)
./scripts/configure.sh

# 3. Set up DNS and firewall (see below)

# 5. Start everything
docker compose up -d

# 6. Create your admin user
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u admin -a \
  http://localhost:8008
```

## DNS Records

Create A records pointing to your VPS IP:

```
matrix.example.com   →  YOUR_VPS_IP
element.example.com  →  YOUR_VPS_IP
livekit.example.com  →  YOUR_VPS_IP
```

### Federation Delegation

If your Matrix IDs should be `@user:example.com` (not `@user:matrix.example.com`), you need `.well-known` delegation from your base domain. Two options:

Configure `.well-known` delegation on your base domain's reverse proxy (e.g., Nginx Proxy Manager). Serve these JSON responses:

```
# Serve at https://example.com/.well-known/matrix/server
{"m.server": "matrix.example.com:443"}

# Serve at https://example.com/.well-known/matrix/client
{"m.homeserver": {"base_url": "https://matrix.example.com"}}
```

Test federation at: https://federationtester.matrix.org/

## Firewall Ports

```bash
# Web + Federation
sudo ufw allow 80,443,8448/tcp
sudo ufw allow 443/udp          # HTTP/3 (optional)

# TURN/STUN for VoIP
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 5349/tcp
sudo ufw allow 5349/udp
sudo ufw allow 49152:49200/udp  # Relay ports

# LiveKit (Element Call)
sudo ufw allow 7881/tcp         # WebRTC TCP fallback
sudo ufw allow 50000:50200/udp  # WebRTC media
```

## Maintenance

```bash
# View logs
docker compose logs -f synapse

# Restart a service
docker compose restart synapse

# Update all images
docker compose pull
docker compose up -d

# Backup database
docker compose exec postgres pg_dump -U synapse synapse > backup.sql

# Restore database
cat backup.sql | docker compose exec -T postgres psql -U synapse synapse
```

## File Structure

```
matrix-synapse-docker/
├── .env.example                    # Copy to .env (hostnames, secrets, Postgres vars)
├── .gitignore
├── docker-compose.yml.example      # Copy to docker-compose.yml (volume paths)
├── coturn/
│   └── turnserver.conf.example     # Copy to turnserver.conf, edit CHANGEME values
├── element/
│   └── config.json.example         # Copy to config.json, edit CHANGEME values
├── livekit/
│   └── config.yaml.example         # Copy to config.yaml, edit CHANGEME values
├── scripts/
│   └── configure.sh                # Interactive setup script for CHANGEME values
└── synapse/
    ├── homeserver.yaml.example     # Copy to homeserver.yaml, edit CHANGEME values
    └── log.config                  # Logging configuration
```

## Redeploying to a New Server

```bash
# On new server:
git clone <this-repo> && cd matrix-synapse-docker
./scripts/configure.sh
docker compose up -d
```

If migrating, also restore your database backup and copy the signing key.

## Troubleshooting

**Federation not working**: Test at https://federationtester.matrix.org/. Most common issues are missing `.well-known` delegation or port 8448 being blocked.

**VoIP calls stuck at "connecting"**: This is almost always a coturn issue. Check that `external-ip` is correct in `coturn/turnserver.conf`, TURN ports are open in the firewall, and the shared secret matches between `homeserver.yaml` and `turnserver.conf`. Test at https://test.voip.librepush.net/.

**Synapse won't start**: Check `docker compose logs synapse`. Common causes are a bad `homeserver.yaml` (YAML is whitespace-sensitive) or PostgreSQL not being ready yet (the healthcheck should handle this).
