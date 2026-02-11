# Matrix Synapse - Docker Compose Deployment

A declarative, repeatable Matrix Synapse deployment with Docker Compose. Includes everything needed for a fully-featured Matrix homeserver with VoIP, screen sharing, and federation.

## What's Included

| Service | Purpose |
|---------|---------|
| **Synapse** | Matrix homeserver |
| **PostgreSQL 16** | Database backend (not SQLite) |
| **Element Web** | Matrix web client |
| **coturn** | TURN/STUN server for VoIP and screen sharing |
| **Caddy** | Reverse proxy with automatic Let's Encrypt TLS |

## Architecture

```
Internet
  │
  ├─ :80/:443/:8448 ──► Caddy (TLS termination)
  │                        ├─► Synapse (:8008) ──► PostgreSQL
  │                        └─► Element Web (:80)
  │
  └─ :3478/:5349/:49152-49200 ──► coturn (host network, TURN/STUN)
```

## Quick Start

```bash
# 1. Clone and enter the directory
git clone <this-repo> && cd matrix-synapse-docker

# 2. Copy example files
cp .env.example .env
cp synapse/homeserver.yaml.example synapse/homeserver.yaml
cp coturn/turnserver.conf.example coturn/turnserver.conf
cp element/config.json.example element/config.json

# 3. Edit all config files — replace every CHANGEME_* value
nano .env                       # Set hostnames and generate a POSTGRES_PASSWORD
nano synapse/homeserver.yaml    # Domain, secrets, database, TURN
nano coturn/turnserver.conf     # TURN secret, external IP
nano element/config.json        # Domain and homeserver URL

# Generate secrets for the config files (run each, paste into the config)
openssl rand -hex 32   # registration_shared_secret
openssl rand -hex 32   # macaroon_secret_key
openssl rand -hex 32   # form_secret
openssl rand -hex 32   # turn_shared_secret (same in homeserver.yaml AND turnserver.conf)

# 4. Set up DNS and firewall (see below)

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
matrix.example.com  →  YOUR_VPS_IP
element.example.com →  YOUR_VPS_IP
```

### Federation Delegation

If your Matrix IDs should be `@user:example.com` (not `@user:matrix.example.com`), you need `.well-known` delegation from your base domain. Two options:

**Option A**: If this Caddy serves your base domain too, uncomment the delegation block in `caddy/Caddyfile`.

**Option B**: If your base domain is served elsewhere (e.g., a separate web server), add this to that server:

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
```

## Maintenance

```bash
# View logs
docker compose logs -f synapse
docker compose logs -f caddy

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
├── .env.example                    # Copy to .env (Caddy + Postgres runtime vars)
├── .gitignore
├── docker-compose.yml              # Service definitions
├── caddy/
│   └── Caddyfile                   # Reverse proxy + TLS config
├── coturn/
│   └── turnserver.conf.example     # Copy to turnserver.conf, edit CHANGEME values
├── element/
│   └── config.json.example         # Copy to config.json, edit CHANGEME values
└── synapse/
    ├── homeserver.yaml.example     # Copy to homeserver.yaml, edit CHANGEME values
    └── log.config                  # Logging configuration
```

## Redeploying to a New Server

```bash
# On new server:
git clone <this-repo> && cd matrix-synapse-docker
cp .env.example .env
cp synapse/homeserver.yaml.example synapse/homeserver.yaml
cp coturn/turnserver.conf.example coturn/turnserver.conf
cp element/config.json.example element/config.json
# Edit .env and all config files (replace CHANGEME values)
docker compose up -d
```

If migrating, also restore your database backup and copy the signing key.

## Troubleshooting

**Caddy won't get certificates**: Ensure ports 80 and 443 are open and DNS is pointing to your VPS. Check `docker compose logs caddy`.

**Federation not working**: Test at https://federationtester.matrix.org/. Most common issues are missing `.well-known` delegation or port 8448 being blocked.

**VoIP calls stuck at "connecting"**: This is almost always a coturn issue. Check that `external-ip` is correct in `coturn/turnserver.conf`, TURN ports are open in the firewall, and the shared secret matches between `homeserver.yaml` and `turnserver.conf`. Test at https://test.voip.librepush.net/.

**Synapse won't start**: Check `docker compose logs synapse`. Common causes are a bad `homeserver.yaml` (YAML is whitespace-sensitive) or PostgreSQL not being ready yet (the healthcheck should handle this).
