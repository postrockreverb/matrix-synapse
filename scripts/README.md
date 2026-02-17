# Scripts

Automation scripts for Matrix Synapse deployment.

## configure.sh

Automates the initial setup by copying example config files and replacing all `CHANGEME_*` placeholders with your values.

### What it does

1. **Copies example files** to their target locations:
   - `.env.example` → `.env`
   - `synapse/homeserver.yaml.example` → `synapse/homeserver.yaml`
   - `coturn/turnserver.conf.example` → `coturn/turnserver.conf`
   - `element/config.json.example` → `element/config.json`
   - `livekit/config.yaml.example` → `livekit/config.yaml`

2. **Prompts for user-provided values**:
   - Base domain (e.g., `example.com`)
   - Synapse hostname (default: `matrix.example.com`)
   - Element hostname (default: `element.example.com`)
   - LiveKit hostname (default: `livekit.example.com`)
   - VPS public IP address
   - PostgreSQL username (default: `synapse`)
   - PostgreSQL database name (default: `synapse`)

3. **Auto-generates secure secrets**:
   - PostgreSQL password (`openssl rand -hex 32`)
   - Registration shared secret (`openssl rand -hex 32`)
   - Macaroon secret (`openssl rand -hex 32`)
   - Form secret (`openssl rand -hex 32`)
   - TURN shared secret (`openssl rand -hex 32`)
   - LiveKit API key (`openssl rand -base64 16`)
   - LiveKit API secret (`openssl rand -base64 32`)

4. **Replaces all `CHANGEME_*` placeholders** across all config files

5. **Verifies** that no `CHANGEME_*` values remain

### Usage

```bash
# From the project root directory
./scripts/configure.sh
```

### Interactive Example

```
$ ./scripts/configure.sh
==============================================================================
Matrix Synapse Configuration Script
==============================================================================

Step 1: Gathering configuration values

Enter your base domain (e.g., example.com): baraso.app
Enter Synapse hostname [matrix.baraso.app]:
Enter Element hostname [element.baraso.app]:
Enter LiveKit hostname [livekit.baraso.app]:

Enter your VPS public IP address: 203.0.113.42

Enter PostgreSQL username [synapse]:
Enter PostgreSQL database name [synapse]:

Step 2: Generating secure secrets

✓ PostgreSQL password: a3f9e2b1c8d7...
✓ Registration shared secret: 7c4d3e2f1a8b...
✓ Macaroon secret: 9e8f7d6c5b4a...
✓ Form secret: 2d3e4f5a6b7c...
✓ TURN shared secret: 8a9b0c1d2e3f...
✓ LiveKit API key: AbCdEfGhIjKl...
✓ LiveKit API secret: MnOpQrStUvWx...

Step 3: Copying example files

✓ Copied .env.example → .env
✓ Copied synapse/homeserver.yaml.example → synapse/homeserver.yaml
✓ Copied coturn/turnserver.conf.example → coturn/turnserver.conf
✓ Copied element/config.json.example → element/config.json
✓ Copied livekit/config.yaml.example → livekit/config.yaml

Step 4: Replacing CHANGEME_* values

✓ Updated .env
✓ Updated synapse/homeserver.yaml
✓ Updated coturn/turnserver.conf
✓ Updated element/config.json
✓ Updated livekit/config.yaml

Step 5: Verification

✓ All CHANGEME_ values have been replaced!

==============================================================================
Configuration Summary
==============================================================================

Domain Configuration:
  Base domain:       baraso.app
  Synapse hostname:  matrix.baraso.app
  Element hostname:  element.baraso.app
  LiveKit hostname:  livekit.baraso.app

Server Configuration:
  VPS IP:            203.0.113.42

Database Configuration:
  User:              synapse
  Database:          synapse

==============================================================================
Next Steps:
==============================================================================

1. Configure DNS A records pointing to 203.0.113.42:
   - matrix.baraso.app
   - element.baraso.app
   - livekit.baraso.app

2. Configure firewall ports (see README.md for details)

3. Start the services:
   docker compose up -d

4. Create your admin user:
   docker compose exec synapse register_new_matrix_user \
     -c /data/homeserver.yaml -u admin -a http://localhost:8008

Configuration complete!
```

### Safety Features

- **Prompts before overwriting**: If target files already exist, asks for confirmation
- **Verification**: Checks that all `CHANGEME_*` values were replaced
- **Preview secrets**: Shows first 16 characters of generated secrets for verification
- **Atomic replacements**: Uses sed with backup files to prevent data loss

### Requirements

- Bash (macOS/Linux)
- `openssl` (for secret generation)
- `sed` (for text replacement)

All requirements are standard on Unix-like systems.
