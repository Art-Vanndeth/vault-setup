#!/bin/sh
# ==============================================================================
# vault/scripts/login-token.sh
# Exchange AppRole credentials for a Vault UI login token.
#
# Usage (from vault-setup/ root):
#   sh vault/scripts/login-token.sh                    <- uses root token (admin)
#   sh vault/scripts/login-token.sh auth-service       <- gets service token
#   sh vault/scripts/login-token.sh payment-service
#
# The printed token can be pasted directly into the Vault UI Token field.
# ==============================================================================

SERVICE="${1:-}"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREDS="$(cd "${SCRIPT_DIR}/.." && pwd)/credentials"

# ── No argument = print root token ───────────────────────────────────────────
if [ -z "$SERVICE" ]; then
  if [ ! -f "${CREDS}/init.json" ]; then
    printf '[ERROR] vault/credentials/init.json not found.\n'
    printf '        Run: docker compose up -d\n'
    exit 1
  fi
  ROOT_TOKEN=$(grep root_token "${CREDS}/init.json" \
    | sed 's/.*"root_token": *"\([^"]*\)".*/\1/')

  printf '\n'
  printf '================================================\n'
  printf '  Vault UI Admin Login\n'
  printf '================================================\n'
  printf '  URL    : http://localhost:8200/ui\n'
  printf '  Method : Token\n'
  printf '  Token  : %s\n' "$ROOT_TOKEN"
  printf '================================================\n\n'
  exit 0
fi

# ── Service argument = exchange AppRole creds for a service token ─────────────
ENV_FILE="${CREDS}/${SERVICE}.env"
if [ ! -f "$ENV_FILE" ]; then
  printf '[ERROR] Not found: %s\n' "$ENV_FILE"
  printf '        Available services:\n'
  for f in "${CREDS}"/*.env; do
    printf '          %s\n' "$(basename "$f" .env)"
  done
  exit 1
fi

# Load credentials
VAULT_ROLE_ID=$(grep VAULT_ROLE_ID "$ENV_FILE" | cut -d= -f2)
VAULT_SECRET_ID=$(grep VAULT_SECRET_ID "$ENV_FILE" | cut -d= -f2)

if [ -z "$VAULT_ROLE_ID" ] || [ -z "$VAULT_SECRET_ID" ]; then
  printf '[ERROR] Could not read VAULT_ROLE_ID or VAULT_SECRET_ID from %s\n' "$ENV_FILE"
  exit 1
fi

# Exchange for client token
printf '\n[INFO] Logging in as AppRole: %s\n' "$SERVICE"
RESPONSE=$(wget -qO- \
  --header="Content-Type: application/json" \
  --post-data="{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
  "${VAULT_ADDR}/v1/auth/approle/login" 2>/dev/null)

# Extract client_token
CLIENT_TOKEN=$(printf '%s' "$RESPONSE" \
  | grep -o '"client_token":"[^"]*"' \
  | sed 's/"client_token":"//;s/"//')

if [ -z "$CLIENT_TOKEN" ]; then
  printf '[ERROR] Login failed. Response:\n%s\n' "$RESPONSE"
  exit 1
fi

printf '\n'
printf '================================================\n'
printf '  Vault UI AppRole Login: %s\n' "$SERVICE"
printf '================================================\n'
printf '  URL    : http://localhost:8200/ui\n'
printf '  Method : Token\n'
printf '  Token  : %s\n' "$CLIENT_TOKEN"
printf '\n'
printf '  NOTE: This token only has access to:\n'
printf '        secret/data/%s\n' "$SERVICE"
printf '================================================\n\n'
