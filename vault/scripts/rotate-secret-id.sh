#!/bin/sh
# ==============================================================================
# vault/scripts/rotate-secret-id.sh  —  Rotate AppRole secret-id
# Usage: sh vault/scripts/rotate-secret-id.sh <service-name>
# ==============================================================================
set -e

SERVICE="${1:-}"
[ -z "$SERVICE" ] && { printf 'Usage: %s <service-name>\n' "$0"; exit 1; }

export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREDS="$(cd "${SCRIPT_DIR}/.." && pwd)/credentials"

if [ -z "$VAULT_TOKEN" ] && [ -f "${CREDS}/init.json" ]; then
  VAULT_TOKEN=$(grep root_token "${CREDS}/init.json" | sed 's/.*: *"\([^"]*\)".*/\1/')
fi
[ -z "$VAULT_TOKEN" ] && { printf '[ERROR] VAULT_TOKEN not set.\n'; exit 1; }
export VAULT_TOKEN

printf '\n===== Rotating secret-id: %s =====\n\n' "$SERVICE"

ROLE_ID=$(vault read -field=role_id "auth/approle/role/${SERVICE}/role-id")
NEW_SECRET_ID=$(vault write -field=secret_id -f "auth/approle/role/${SERVICE}/secret-id")

cat > "${CREDS}/${SERVICE}.env" <<ENV
# AppRole credentials for: ${SERVICE}  [ROTATED]
# DO NOT COMMIT
VAULT_ADDR=${VAULT_ADDR}
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${NEW_SECRET_ID}
ENV
chmod 600 "${CREDS}/${SERVICE}.env"

printf '[DONE] New secret-id for [%s]\n' "$SERVICE"
printf '  VAULT_SECRET_ID = %s\n' "$NEW_SECRET_ID"
printf '  File updated    = %s\n' "${CREDS}/${SERVICE}.env"
printf '\n[WARN] Restart %s to pick up the new secret-id.\n\n' "$SERVICE"
