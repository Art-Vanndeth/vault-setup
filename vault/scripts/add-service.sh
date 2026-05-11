#!/bin/sh
# ==============================================================================
# vault/scripts/add-service.sh  —  Register a new microservice in Vault
#
# Run from the project root directory.
#
# PowerShell:
#   $env:VAULT_ADDR="http://localhost:8200"
#   $env:VAULT_TOKEN=(Get-Content vault\credentials\init.json | ConvertFrom-Json).root_token
#   sh vault/scripts/add-service.sh order-service
#
# Git Bash / WSL:
#   export VAULT_ADDR=http://localhost:8200
#   export VAULT_TOKEN=$(grep root_token vault/credentials/init.json | sed 's/.*: *"\([^"]*\)".*/\1/')
#   sh vault/scripts/add-service.sh order-service
# ==============================================================================
set -e

SERVICE="${1:-}"
[ -z "$SERVICE" ] && { printf 'Usage: %s <service-name>\n' "$0"; exit 1; }

export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CREDS="${VAULT_DIR}/credentials"
POLICIES="${VAULT_DIR}/policies"

# Auto-load token from saved file
if [ -z "$VAULT_TOKEN" ] && [ -f "${CREDS}/init.json" ]; then
  VAULT_TOKEN=$(grep root_token "${CREDS}/init.json" | sed 's/.*: *"\([^"]*\)".*/\1/')
fi
[ -z "$VAULT_TOKEN" ] && { printf '[ERROR] VAULT_TOKEN not set.\n'; exit 1; }
export VAULT_TOKEN

printf '\n===== Adding service: %s =====\n\n' "$SERVICE"

# 1. Create policy file
POLICY_FILE="${POLICIES}/${SERVICE}.hcl"
if [ ! -f "$POLICY_FILE" ]; then
  cat > "$POLICY_FILE" <<HCL
# Policy: ${SERVICE} (auto-generated)
path "secret/data/${SERVICE}" {
  capabilities = ["read"]
}
path "secret/metadata/${SERVICE}" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
HCL
  printf '[INFO] Policy file: %s\n' "$POLICY_FILE"
fi

# 2. Apply policy
vault policy write "$SERVICE" "$POLICY_FILE"
printf '[INFO] Policy applied: %s\n' "$SERVICE"

# 3. Create AppRole
vault write "auth/approle/role/${SERVICE}" \
  policies="$SERVICE" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0 >/dev/null
printf '[INFO] AppRole created.\n'

# 4. Get credentials
ROLE_ID=$(vault read -field=role_id "auth/approle/role/${SERVICE}/role-id")
SECRET_ID=$(vault write -field=secret_id -f "auth/approle/role/${SERVICE}/secret-id")

# 5. Write .env
cat > "${CREDS}/${SERVICE}.env" <<ENV
# AppRole credentials for: ${SERVICE}
# DO NOT COMMIT
VAULT_ADDR=${VAULT_ADDR}
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${SECRET_ID}
ENV
chmod 600 "${CREDS}/${SERVICE}.env"

# 6. Seed placeholder secret
vault kv put "secret/${SERVICE}" \
  "spring.datasource.url=CHANGE_ME" \
  "spring.datasource.username=CHANGE_ME" \
  "spring.datasource.password=CHANGE_ME" >/dev/null

printf '\n[DONE] %s\n' "$SERVICE"
printf '  VAULT_ROLE_ID   = %s\n' "$ROLE_ID"
printf '  VAULT_SECRET_ID = %s\n' "$SECRET_ID"
printf '  Env file        = %s\n' "${CREDS}/${SERVICE}.env"
printf '\nUpdate secrets:\n  vault kv put secret/%s key=value ...\n\n' "$SERVICE"
