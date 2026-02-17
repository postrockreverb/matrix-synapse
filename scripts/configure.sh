#!/usr/bin/env bash
# =============================================================================
# Matrix Synapse Configuration Script
# =============================================================================
# This script automates the setup process by:
# 1. Copying .example files to their target locations
# 2. Prompting for user-provided values (domain, hostnames, IP)
# 3. Auto-generating secure secrets
# 4. Replacing all CHANGEME_* values in config files
# =============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Matrix Synapse Configuration Script${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo

# =============================================================================
# Helper Functions
# =============================================================================

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    read -p "$(echo -e "${YELLOW}$prompt${NC} ${GREEN}[$default]${NC}: ")" result
    echo "${result:-$default}"
}

prompt_required() {
    local prompt="$1"
    local result

    while [ -z "$result" ]; do
        read -p "$(echo -e "${YELLOW}$prompt${NC}: ")" result
        if [ -z "$result" ]; then
            echo -e "${RED}This value is required. Please try again.${NC}"
        fi
    done
    echo "$result"
}

generate_secret_hex32() {
    openssl rand -hex 32
}

generate_secret_base64_16() {
    openssl rand -base64 16
}

generate_secret_base64_32() {
    openssl rand -base64 32
}

# =============================================================================
# Gather User Input
# =============================================================================

echo -e "${GREEN}Step 1: Gathering configuration values${NC}"
echo

# Domain configuration
DOMAIN=$(prompt_required "Enter your base domain (e.g., example.com)")
SYNAPSE_HOSTNAME=$(prompt_with_default "Enter Synapse hostname" "synapse.$DOMAIN")
ELEMENT_HOSTNAME=$(prompt_with_default "Enter Element hostname" "element.$DOMAIN")
LIVEKIT_HOSTNAME=$(prompt_with_default "Enter LiveKit hostname" "livekit.$DOMAIN")

echo
# VPS configuration
VPS_PUBLIC_IP=$(prompt_required "Enter your VPS public IP address")

echo
# Database configuration
POSTGRES_USER=$(prompt_with_default "Enter PostgreSQL username" "synapse")
POSTGRES_DB=$(prompt_with_default "Enter PostgreSQL database name" "synapse")

echo

# =============================================================================
# Generate Secrets
# =============================================================================

echo -e "${GREEN}Step 2: Generating secure secrets${NC}"
echo

POSTGRES_PASSWORD=$(generate_secret_hex32)
echo -e "✓ PostgreSQL password: ${POSTGRES_PASSWORD:0:16}..."

REGISTRATION_SECRET=$(generate_secret_hex32)
echo -e "✓ Registration shared secret: ${REGISTRATION_SECRET:0:16}..."

MACAROON_SECRET=$(generate_secret_hex32)
echo -e "✓ Macaroon secret: ${MACAROON_SECRET:0:16}..."

FORM_SECRET=$(generate_secret_hex32)
echo -e "✓ Form secret: ${FORM_SECRET:0:16}..."

TURN_SECRET=$(generate_secret_hex32)
echo -e "✓ TURN shared secret: ${TURN_SECRET:0:16}..."

LIVEKIT_API_KEY=$(generate_secret_base64_16)
echo -e "✓ LiveKit API key: ${LIVEKIT_API_KEY:0:16}..."

LIVEKIT_API_SECRET=$(generate_secret_base64_32)
echo -e "✓ LiveKit API secret: ${LIVEKIT_API_SECRET:0:16}..."

echo

# =============================================================================
# Copy Example Files
# =============================================================================

echo -e "${GREEN}Step 3: Copying example files${NC}"
echo

FILES=(
    ".env.example:.env"
    "synapse/homeserver.yaml.example:synapse/homeserver.yaml"
    "coturn/turnserver.conf.example:coturn/turnserver.conf"
    "element/config.json.example:element/config.json"
    "livekit/config.yaml.example:livekit/config.yaml"
)

for file_pair in "${FILES[@]}"; do
    IFS=':' read -r source target <<< "$file_pair"
    source_path="$PROJECT_ROOT/$source"
    target_path="$PROJECT_ROOT/$target"

    if [ -f "$target_path" ]; then
        echo -e "${YELLOW}⚠ $target already exists${NC}"
        read -p "$(echo -e "${YELLOW}Overwrite? (y/N)${NC}: ")" overwrite
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            echo -e "Skipping $target"
            continue
        fi
    fi

    cp "$source_path" "$target_path"
    echo -e "✓ Copied $source → $target"
done

echo

# =============================================================================
# Replace CHANGEME Values
# =============================================================================

echo -e "${GREEN}Step 4: Replacing CHANGEME_* values${NC}"
echo

# Create a temporary sed script for all replacements
SED_SCRIPT=$(mktemp)

cat > "$SED_SCRIPT" << EOF
s|CHANGEME_DOMAIN|$DOMAIN|g
s|CHANGEME_SYNAPSE_HOSTNAME|$SYNAPSE_HOSTNAME|g
s|CHANGEME_ELEMENT_HOSTNAME|$ELEMENT_HOSTNAME|g
s|CHANGEME_LIVEKIT_HOSTNAME|$LIVEKIT_HOSTNAME|g
s|CHANGEME_VPS_PUBLIC_IP|$VPS_PUBLIC_IP|g
s|CHANGEME_POSTGRES_USER|$POSTGRES_USER|g
s|CHANGEME_POSTGRES_PASSWORD|$POSTGRES_PASSWORD|g
s|CHANGEME_POSTGRES_DB|$POSTGRES_DB|g
s|CHANGEME_REGISTRATION_SECRET|$REGISTRATION_SECRET|g
s|CHANGEME_MACAROON_SECRET|$MACAROON_SECRET|g
s|CHANGEME_FORM_SECRET|$FORM_SECRET|g
s|CHANGEME_TURN_SECRET|$TURN_SECRET|g
s|CHANGEME_LIVEKIT_API_KEY|$LIVEKIT_API_KEY|g
s|CHANGEME_LIVEKIT_API_SECRET|$LIVEKIT_API_SECRET|g
EOF

# Apply replacements to each config file
CONFIG_FILES=(
    ".env"
    "synapse/homeserver.yaml"
    "coturn/turnserver.conf"
    "element/config.json"
    "livekit/config.yaml"
)

for config_file in "${CONFIG_FILES[@]}"; do
    config_path="$PROJECT_ROOT/$config_file"

    if [ -f "$config_path" ]; then
        # Check if file has any CHANGEME_ values before processing
        if grep -q "CHANGEME_" "$config_path"; then
            sed -i.bak -f "$SED_SCRIPT" "$config_path"
            rm -f "${config_path}.bak"
            echo -e "✓ Updated $config_file"
        else
            echo -e "  $config_file (no CHANGEME_ values found)"
        fi
    else
        echo -e "${YELLOW}⚠ $config_file not found (skipped)${NC}"
    fi
done

# Clean up
rm -f "$SED_SCRIPT"

echo

# =============================================================================
# Verification
# =============================================================================

echo -e "${GREEN}Step 5: Verification${NC}"
echo

# Check if any CHANGEME_ values remain
REMAINING_FILES=()
for config_file in "${CONFIG_FILES[@]}"; do
    config_path="$PROJECT_ROOT/$config_file"
    if [ -f "$config_path" ] && grep -q "CHANGEME_" "$config_path"; then
        REMAINING_FILES+=("$config_file")
    fi
done

if [ ${#REMAINING_FILES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warning: The following files still contain CHANGEME_ values:${NC}"
    for file in "${REMAINING_FILES[@]}"; do
        echo -e "  - $file"
    done
    echo
    echo -e "${YELLOW}You may need to manually edit these files.${NC}"
else
    echo -e "${GREEN}✓ All CHANGEME_ values have been replaced!${NC}"
fi

echo

# =============================================================================
# Summary
# =============================================================================

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Configuration Summary${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo
echo -e "${GREEN}Domain Configuration:${NC}"
echo -e "  Base domain:       $DOMAIN"
echo -e "  Synapse hostname:  $SYNAPSE_HOSTNAME"
echo -e "  Element hostname:  $ELEMENT_HOSTNAME"
echo -e "  LiveKit hostname:  $LIVEKIT_HOSTNAME"
echo
echo -e "${GREEN}Server Configuration:${NC}"
echo -e "  VPS IP:            $VPS_PUBLIC_IP"
echo
echo -e "${GREEN}Database Configuration:${NC}"
echo -e "  User:              $POSTGRES_USER"
echo -e "  Database:          $POSTGRES_DB"
echo
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo
echo "1. Configure DNS A records pointing to $VPS_PUBLIC_IP:"
echo "   - $SYNAPSE_HOSTNAME"
echo "   - $ELEMENT_HOSTNAME"
echo "   - $LIVEKIT_HOSTNAME"
echo
echo "2. Configure firewall ports (see README.md for details)"
echo
echo "3. Start the services:"
echo "   docker compose up -d"
echo
echo "4. Create your admin user:"
echo "   docker compose exec synapse register_new_matrix_user \\"
echo "     -c /data/homeserver.yaml -u admin -a http://localhost:8008"
echo
echo -e "${GREEN}Configuration complete!${NC}"
echo
