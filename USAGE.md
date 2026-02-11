# Usage Guide

## Accessing Your Server

- **Element Web Client**: https://element.baraso.app
- **Your Matrix ID**: `@yourname:baraso.app`
- **Homeserver URL** (for other clients): `matrix.baraso.app`

Any Matrix client (Element mobile, FluffyChat, Nheko, etc.) can connect using `matrix.baraso.app` as the homeserver.

## User Management

### Create an admin user

```bash
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml -u USERNAME -a \
  http://localhost:8008
```

### Create a non-admin user

```bash
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml -u USERNAME \
  http://localhost:8008
```

Both commands will prompt for a password.

### Token-based registration

With `enable_registration: true` and `registration_requires_token: true` in `homeserver.yaml`, users can self-register with an invite token.

**Get your admin access token** from Element: Settings > Help & About > Advanced > Access Token.

```bash
# Create a single-use invite token
curl -s -X POST "http://localhost:8008/_synapse/admin/v1/registration_tokens/new" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"uses_allowed": 1}' | python3 -m json.tool

# Create a multi-use token (e.g. 5 uses)
curl -s -X POST "http://localhost:8008/_synapse/admin/v1/registration_tokens/new" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"uses_allowed": 5}' | python3 -m json.tool

# List all tokens
curl -s "http://localhost:8008/_synapse/admin/v1/registration_tokens" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" | python3 -m json.tool

# Delete a token
curl -s -X DELETE "http://localhost:8008/_synapse/admin/v1/registration_tokens/TOKEN" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

Share the token with the person you want to invite — they enter it during registration on Element.

## Day-to-Day Operations

### View logs

```bash
docker compose logs -f                # All services
docker compose logs -f synapse        # Just Synapse
docker compose logs -f caddy          # Just Caddy
docker compose logs -f postgres       # Just Postgres
```

### Restart services

```bash
docker compose restart synapse
docker compose restart caddy
docker compose restart               # All services
```

### Update images

```bash
docker compose pull
docker compose up -d
```

### Stop / start everything

```bash
docker compose down                   # Stop all
docker compose up -d                  # Start all
```

## Backups

### Database

```bash
# Backup
docker compose exec postgres pg_dump -U synapse synapse > backup.sql

# Restore
cat backup.sql | docker compose exec -T postgres psql -U synapse synapse
```

### Signing key

The signing key at `synapse/signing.key` is critical for federation identity. Back it up — if you lose it, other servers won't trust yours anymore.

### Media

Media files are stored in the `synapse_media` Docker volume. Back it up with:

```bash
docker run --rm -v matrix-synapse_synapse_media:/data -v $(pwd):/backup alpine \
  tar czf /backup/media_backup.tar.gz -C /data .
```

## Federation

- **Test federation**: https://federationtester.matrix.org/ — enter `baraso.app`
- **Test TURN/VoIP**: https://test.voip.librepush.net/

Federation lets you communicate with users on any other Matrix server. Your users can join rooms on `matrix.org` or any other federated server.

## Troubleshooting

**Can't connect to Element**: Check `docker compose logs caddy`. Usually a DNS or certificate issue.

**Synapse won't start**: Check `docker compose logs synapse`. Common causes are YAML syntax errors in `homeserver.yaml`.

**VoIP calls not working**: Check that the TURN shared secret matches in both `homeserver.yaml` and `turnserver.conf`, and that ports 3478, 5349, and 49152-49200 are open.

**Federation failing**: Run the federation tester above. Usually missing `.well-known` delegation or port 8448 being blocked.

## Important Files on the Server

| File | Purpose |
|------|---------|
| `.env` | Hostnames and Postgres credentials |
| `synapse/homeserver.yaml` | Main Synapse configuration |
| `coturn/turnserver.conf` | TURN server configuration |
| `element/config.json` | Element web client configuration |
| `caddy/Caddyfile` | Reverse proxy and TLS |
| `synapse/signing.key` | Federation identity (back this up!) |
