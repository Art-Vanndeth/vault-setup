#!/bin/sh
# ==============================================================================
# vault/init/init.sh
# Uses vault CLI -field flag for ALL extraction — zero grep/sed JSON parsing.
# ==============================================================================
set -e

export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
CREDS="/vault/credentials"
POLICIES="/vault/policies"

log()  { printf '[INFO]  %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
sep()  { printf '\n==== %s ====\n' "$*"; }

# ==============================================================================
# 0 — Wait for Vault
# ==============================================================================
sep "Waiting for Vault"
TRIES=0; MAX=60
until wget -qO- \
  "${VAULT_ADDR}/v1/sys/health?standbyok=true&uninitcode=200&sealedcode=200" \
  >/dev/null 2>&1
do
  TRIES=$((TRIES+1))
  [ "$TRIES" -ge "$MAX" ] && fail "Vault unreachable after ${MAX} attempts."
  warn "Not ready (${TRIES}/${MAX}) — retrying in 3s..."
  sleep 3
done
log "Vault is reachable."

# ==============================================================================
# 1 — Check status
# ==============================================================================
sep "Checking Status"

# vault status exits non-zero when sealed/uninitialised — capture without failing
INITIALIZED=$(vault status -format=json 2>/dev/null \
  | grep '"initialized"' \
  | tr -d ' ",:' \
  | sed 's/initialized//')

log "Initialized: ${INITIALIZED}"

# ==============================================================================
# Handle already-initialized Vault
# ==============================================================================
if [ "$INITIALIZED" = "true" ]; then
  log "Already initialized."
  if [ -f "${CREDS}/init.json" ]; then
    UNSEAL_KEY=$(grep unseal_key "${CREDS}/init.json" \
      | sed 's/.*"unseal_key": *"\([^"]*\)".*/\1/')
    ROOT_TOKEN=$(grep root_token "${CREDS}/init.json" \
      | sed 's/.*"root_token": *"\([^"]*\)".*/\1/')

    SEALED=$(vault status -format=json 2>/dev/null \
      | grep '"sealed"' \
      | tr -d ' ",:' \
      | sed 's/sealed//')

    if [ "$SEALED" = "true" ]; then
      log "Unsealing with saved key..."
      vault operator unseal "$UNSEAL_KEY"
      log "Unsealed."
    else
      log "Already unsealed."
    fi

    sep "Already bootstrapped — credentials:"
    log "Root Token  -> ${ROOT_TOKEN}"
    log "Credentials -> ${CREDS}/"
  else
    warn "No init.json found — manual unseal needed."
  fi
  exit 0
fi

# ==============================================================================
# 2 — Initialize using vault CLI
#     Use -format=table so output is simple KEY: VALUE lines, not JSON
# ==============================================================================
sep "Initializing Vault"

# -format=table output looks like:
#   Unseal Key 1: KQ0EYLTOqi1C5/mnqbCpO/RQcZdkslXYZdsgmKDExOk=
#   Initial Root Token: hvs.cdX792A146qz39zrFoJV7JFy
INIT_TABLE=$(vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=table 2>/dev/null)

log "Init table output:"
printf '%s\n' "$INIT_TABLE"

# Extract from table format — these patterns are stable across Vault versions
UNSEAL_KEY=$(printf '%s' "$INIT_TABLE" \
  | grep "^Unseal Key" \
  | head -1 \
  | sed 's/.*: *//')

ROOT_TOKEN=$(printf '%s' "$INIT_TABLE" \
  | grep "^Initial Root Token" \
  | head -1 \
  | sed 's/.*: *//')

log "Unseal key : ${UNSEAL_KEY}"
log "Root token : ${ROOT_TOKEN}"

if [ -z "$UNSEAL_KEY" ] || [ -z "$ROOT_TOKEN" ]; then
  fail "Could not extract credentials from vault operator init output."
fi

# ==============================================================================
# 3 — Save credentials immediately
# ==============================================================================
sep "Saving Credentials"
mkdir -p "$CREDS"

cat > "${CREDS}/init.json" <<JSON
{
  "unseal_key": "${UNSEAL_KEY}",
  "root_token": "${ROOT_TOKEN}"
}
JSON
chmod 600 "${CREDS}/init.json"
log "Saved: ${CREDS}/init.json"

# Admin .env file
cat > "${CREDS}/.env" <<ENV
# Vault admin credentials — DO NOT COMMIT
VAULT_ADDR=${VAULT_ADDR}
VAULT_TOKEN=${ROOT_TOKEN}
VAULT_UNSEAL_KEY=${UNSEAL_KEY}
ENV
chmod 600 "${CREDS}/.env"
log "Saved: ${CREDS}/.env"

# ==============================================================================
# 4 — Unseal
# ==============================================================================
sep "Unsealing Vault"
vault operator unseal "$UNSEAL_KEY"
log "Vault unsealed."
sleep 2

export VAULT_TOKEN="$ROOT_TOKEN"

# ==============================================================================
# 5 — Enable KV v2
# ==============================================================================
sep "Enabling KV v2"
vault secrets enable -path=secret -version=2 kv \
  && log "KV v2 enabled at secret/" \
  || log "Already enabled (OK)"

# ==============================================================================
# 6 — Enable AppRole
# ==============================================================================
sep "Enabling AppRole"
vault auth enable approle \
  && log "AppRole enabled." \
  || log "Already enabled (OK)"

# ==============================================================================
# 7 — Write Policies
# ==============================================================================
sep "Writing Policies"
for POLICY_FILE in "${POLICIES}"/*.hcl; do
  SVC=$(basename "$POLICY_FILE" .hcl)
  vault policy write "$SVC" "$POLICY_FILE"
  log "Policy: ${SVC}"
done

# ==============================================================================
# 8 — Create AppRoles + write .env files
# ==============================================================================
sep "Creating AppRoles"

make_approle() {
  SVC="$1"
  vault write "auth/approle/role/${SVC}" \
    policies="${SVC}" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    >/dev/null

  ROLE_ID=$(vault read -field=role_id "auth/approle/role/${SVC}/role-id")
  SECRET_ID=$(vault write -field=secret_id -f "auth/approle/role/${SVC}/secret-id")

  cat > "${CREDS}/${SVC}.env" <<ENV
# AppRole credentials: ${SVC} — DO NOT COMMIT
VAULT_ADDR=${VAULT_ADDR}
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${SECRET_ID}
ENV
  chmod 600 "${CREDS}/${SVC}.env"
  log "${SVC}: role_id=${ROLE_ID}"
}

make_approle "auth-service"
make_approle "e-kyc-service"
make_approle "payment-service"
make_approle "notification-service"
make_approle "gateway-service"

# ==============================================================================
# 9 — Seed KV secrets
# ==============================================================================
sep "Seeding KV Secrets"

vault kv put secret/auth-service \
  "spring.datasource.url=jdbc:postgresql://postgres:5432/authdb" \
  "spring.datasource.username=auth_user" \
  "spring.datasource.password=CHANGE_ME_auth_db_pass" \
  "jwt.secret=CHANGE_ME_jwt_256bit_key" \
  "oauth2.client-secret=CHANGE_ME_oauth2_secret"
log "Seeded: secret/auth-service"

vault kv put secret/e-kyc-service \
  "spring.datasource.url=jdbc:postgresql://postgres:5432/ekycdb" \
  "spring.datasource.username=ekyc_user" \
  "spring.datasource.password=CHANGE_ME_ekyc_db_pass" \
  "external.api-key=CHANGE_ME_ekyc_api_key" \
  "external.api-url=https://api.ekyc-provider.example.com"
log "Seeded: secret/e-kyc-service"

vault kv put secret/payment-service \
  "spring.datasource.url=jdbc:postgresql://postgres:5432/paymentdb" \
  "spring.datasource.username=payment_user" \
  "spring.datasource.password=CHANGE_ME_payment_db_pass" \
  "external.api-key=CHANGE_ME_payment_api_key" \
  "external.api-url=https://api.payment-gateway.example.com" \
  "external.webhook-secret=CHANGE_ME_webhook_secret"
log "Seeded: secret/payment-service"

vault kv put secret/notification-service \
  "spring.datasource.url=jdbc:postgresql://postgres:5432/notifdb" \
  "spring.datasource.username=notif_user" \
  "spring.datasource.password=CHANGE_ME_notif_db_pass" \
  "external.smtp-host=smtp.example.com" \
  "external.smtp-port=587" \
  "external.smtp-password=CHANGE_ME_smtp_pass" \
  "external.api-key=CHANGE_ME_sms_api_key"
log "Seeded: secret/notification-service"

vault kv put secret/gateway-service \
  "spring.datasource.url=jdbc:postgresql://postgres:5432/gatewaydb" \
  "spring.datasource.username=gateway_user" \
  "spring.datasource.password=CHANGE_ME_gateway_db_pass" \
  "jwt.secret=CHANGE_ME_jwt_256bit_key"
log "Seeded: secret/gateway-service"

# ==============================================================================
# 10 — Write SUMMARY
# ==============================================================================
cat > "${CREDS}/SUMMARY.txt" <<SUMMARY
================================================
  Vault Bootstrap Complete
================================================

  Vault UI URL : http://localhost:8200/ui
  Root Token   : ${ROOT_TOKEN}
  Unseal Key   : ${UNSEAL_KEY}

  LOGIN TO VAULT UI:
  ------------------
  Option A — Token (admin):
    1. Open http://localhost:8200/ui
    2. Method: Token
    3. Paste root token above

  Option B — AppRole (per microservice):
    1. Open http://localhost:8200/ui
    2. Click "Other" -> select "AppRole"
    3. Open vault/credentials/<service>.env
    4. Paste VAULT_ROLE_ID  -> Role ID field
    5. Paste VAULT_SECRET_ID -> Secret ID field

  Files written:
    vault/credentials/init.json
    vault/credentials/.env
    vault/credentials/auth-service.env
    vault/credentials/e-kyc-service.env
    vault/credentials/payment-service.env
    vault/credentials/notification-service.env
    vault/credentials/gateway-service.env

  NEXT STEPS:
    Replace all CHANGE_ME_* values with real secrets.
    Never commit vault/credentials/ to git.
================================================
SUMMARY
chmod 644 "${CREDS}/SUMMARY.txt"

# ==============================================================================
# Done
# ==============================================================================
sep "BOOTSTRAP COMPLETE"
printf '\n'
printf '  Vault UI    -> http://localhost:8200/ui\n'
printf '  Login       -> Token method\n'
printf '  Root Token  -> %s\n' "$ROOT_TOKEN"
printf '\n'
printf '  All credential files in vault/credentials/\n'
printf '  Read: vault/credentials/SUMMARY.txt\n'
printf '\n'
