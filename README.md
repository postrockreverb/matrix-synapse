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

# 3. Set up DNS, firewall, and Nginx Proxy Manager (see below)

# 4. Start everything
docker compose up -d

# 5. Create your admin user
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

## Nginx Proxy Manager Setup

This deployment expects an external Nginx Proxy Manager (NPM) instance. All containers join NPM's Docker network (`npm_external`) and are accessed by container name.

Create the following proxy hosts and stream in NPM:

### 1. Base domain — `example.com`

Handles `.well-known` federation delegation so Matrix IDs can be `@user:example.com`.

| Setting | Value |
|---------|-------|
| Domain Names | `example.com` |
| Scheme | `http` |
| Forward Hostname/IP | `matrix-synapse` |
| Forward Port | `8008` |
| SSL | Force SSL, HTTP/2 Support |

**Advanced tab** — custom Nginx configuration:

```nginx
location /.well-known/matrix/server {
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '{"m.server": "matrix.example.com:443"}';
}

location /.well-known/matrix/client {
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '{"m.homeserver": {"base_url": "https://matrix.example.com"}, "org.matrix.msc4143.rtc_foci": [{"type": "livekit", "livekit_service_url": "https://livekit.example.com"}]}';
}
```

### 2. Synapse — `matrix.example.com`

| Setting | Value |
|---------|-------|
| Domain Names | `matrix.example.com` |
| Scheme | `http` |
| Forward Hostname/IP | `matrix-synapse` |
| Forward Port | `8008` |
| Websockets Support | on |
| SSL | Force SSL, HTTP/2 Support |

### 3. Element Web — `element.example.com`

| Setting | Value |
|---------|-------|
| Domain Names | `element.example.com` |
| Scheme | `http` |
| Forward Hostname/IP | `matrix-element` |
| Forward Port | `80` |
| SSL | Force SSL, HTTP/2 Support |

**Advanced tab** — custom Nginx configuration (required for Element Call E2EE and security headers):

```nginx
location / {
    proxy_pass $forward_scheme://$server:$port;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header Cross-Origin-Opener-Policy "same-origin";
    add_header Cross-Origin-Embedder-Policy "credentialless";
}
```

> **Note**: The custom `location /` block is required because NPM ignores `add_header` directives placed at the top level of the Advanced tab. The `proxy_pass` must be included since this block replaces NPM's generated one.

### 4. LiveKit — `livekit.example.com`

| Setting | Value |
|---------|-------|
| Domain Names | `livekit.example.com` |
| Scheme | `http` |
| Forward Hostname/IP | `matrix-livekit` |
| Forward Port | `7880` |
| Websockets Support | on |
| SSL | Force SSL, HTTP/2 Support |

**Advanced tab** — custom Nginx configuration (routes JWT token endpoints to lk-jwt-service):

```nginx
location /sfu/get {
    proxy_pass http://matrix-lk-jwt-service:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location /get_token {
    proxy_pass http://matrix-lk-jwt-service:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location /healthz {
    proxy_pass http://matrix-lk-jwt-service:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

### 5. Federation fallback — port 8448 (Stream)

In NPM go to **Streams** (not Proxy Hosts):

| Setting | Value |
|---------|-------|
| Incoming Port | `8448` |
| Forward Host | `matrix-synapse` |
| Forward Port | `8008` |
| TCP Forwarding | on |

> Modern federation uses port 443 with `.well-known` delegation (step 1). The 8448 stream is a fallback for legacy servers.

### Federation Delegation

If your Matrix IDs should be `@user:example.com` (not `@user:matrix.example.com`), the `.well-known` endpoints in step 1 handle this. The base domain (`example.com`) must be served by NPM with a proxy host as described above.

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
