# Centralized HashiCorp Vault — Production Setup
`hashicorp/vault:2.0` · AppRole · KV v2 · File Backend · Docker Compose

---

## Folder Structure

```
vault-setup/
├── docker-compose.yml
├── .gitignore
├── README.md
│
├── vault/
│   ├── config/
│   │   └── vault.hcl
│   ├── init/
│   │   └── init.sh                      Auto-runs on first docker compose up
│   ├── policies/
│   │   ├── auth-service.hcl
│   │   ├── e-kyc-service.hcl
│   │   ├── payment-service.hcl
│   │   ├── notification-service.hcl
│   │   └── gateway-service.hcl
│   ├── credentials/                     AUTO-GENERATED — never commit
│   │   ├── init.json                    unseal key + root token
│   │   ├── .env                         admin env vars (source this)
│   │   ├── SUMMARY.txt                  human-readable summary
│   │   ├── auth-service.env
│   │   ├── e-kyc-service.env
│   │   ├── payment-service.env
│   │   ├── notification-service.env
│   │   └── gateway-service.env
│   └── scripts/
│       ├── add-service.sh
│       └── rotate-secret-id.sh
│
└── microservices/
    ├── _template/
    ├── auth-service/
    ├── e-kyc-service/
    ├── payment-service/
    ├── notification-service/
    └── gateway-service/
```

---

## Start

```powershell
# Full reset (first time or after errors)
docker compose down -v

# Start — this runs 3 containers:
#   1. vault-permissions  (fixes /vault/data ownership, exits)
#   2. vault              (server, stays running)
#   3. vault-init         (bootstrap, exits when done)
docker compose up -d

# Watch bootstrap — takes ~15 seconds
docker logs -f vault-init
```

When you see `BOOTSTRAP COMPLETE` in the logs, credentials are written.

---

## Get Your Login Token

```powershell
# From project root (vault-setup/)
Get-Content vault\credentials\init.json
```

Output:
```json
{
  "unseal_key": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "root_token": "hvs.xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

The `root_token` value is what you use to log in.

Also check the full summary:
```powershell
Get-Content vault\credentials\SUMMARY.txt
```

---

## Logging into Vault UI

### Method A — Token (Admin / Ops)

1. Open **http://localhost:8200/ui**
2. Sign-in method: **Token**
3. Paste the `root_token` from `vault/credentials/init.json`
4. Click **Sign In**

```powershell
# Quick copy of root token
(Get-Content vault\credentials\init.json | ConvertFrom-Json).root_token
```

---

### Method B — AppRole (how microservices authenticate)

This is the production method. Each microservice logs in with its own Role ID + Secret ID.

1. Open **http://localhost:8200/ui**
2. Click **"Other"** at the bottom of the sign-in page
3. Select **AppRole** from the method list
4. Open the service's credential file:

```powershell
# Example: auth-service
Get-Content vault\credentials\auth-service.env
```

Output:
```
VAULT_ADDR=http://vault:8200
VAULT_ROLE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
VAULT_SECRET_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
```

5. Enter `VAULT_ROLE_ID` in the **Role ID** field
6. Enter `VAULT_SECRET_ID` in the **Secret ID** field
7. Click **Sign In**

The AppRole session will only be able to see `secret/auth-service` — exactly as the policy allows. This is the least-privilege model.

---

### Method C — AppRole via CLI (test / debug)

```bash
# Git Bash / WSL from project root
export VAULT_ADDR=http://localhost:8200

# Load a service's credentials
source vault/credentials/auth-service.env

# Login — gets a short-lived service token
vault write auth/approle/login \
  role_id="$VAULT_ROLE_ID" \
  secret_id="$VAULT_SECRET_ID"

# Use the returned client_token to read secrets
export VAULT_TOKEN="<client_token from above>"
vault kv get secret/auth-service
```

---

### Method D — AppRole via curl

```bash
export VAULT_ADDR=http://localhost:8200
source vault/credentials/auth-service.env

# Step 1: Login and get a service token
CLIENT_TOKEN=$(curl -sf --request POST \
  --data "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" \
  "$VAULT_ADDR/v1/auth/approle/login" \
  | grep -o '"client_token":"[^"]*"' \
  | sed 's/"client_token":"//;s/"//')

echo "Token: $CLIENT_TOKEN"

# Step 2: Read secrets with that token
curl -sf \
  -H "X-Vault-Token: $CLIENT_TOKEN" \
  "$VAULT_ADDR/v1/secret/data/auth-service"
```

---

## KV Secret Structure

All secrets are at `secret/<service-name>`:

```
secret/auth-service
  spring.datasource.url      = jdbc:postgresql://postgres:5432/authdb
  spring.datasource.username = auth_user
  spring.datasource.password = CHANGE_ME_auth_db_pass
  jwt.secret                 = CHANGE_ME_jwt_256bit_key
  oauth2.client-secret       = CHANGE_ME_oauth2_secret

secret/e-kyc-service
  spring.datasource.url      = jdbc:postgresql://postgres:5432/ekycdb
  spring.datasource.username = ekyc_user
  spring.datasource.password = CHANGE_ME_ekyc_db_pass
  external.api-key           = CHANGE_ME_ekyc_api_key
  external.api-url           = https://api.ekyc-provider.example.com

secret/payment-service
  spring.datasource.url      = jdbc:postgresql://postgres:5432/paymentdb
  spring.datasource.username = payment_user
  spring.datasource.password = CHANGE_ME_payment_db_pass
  external.api-key           = CHANGE_ME_payment_api_key
  external.api-url           = https://api.payment-gateway.example.com
  external.webhook-secret    = CHANGE_ME_webhook_secret

secret/notification-service
  spring.datasource.url      = jdbc:postgresql://postgres:5432/notifdb
  spring.datasource.username = notif_user
  spring.datasource.password = CHANGE_ME_notif_db_pass
  external.smtp-host         = smtp.example.com
  external.smtp-port         = 587
  external.smtp-password     = CHANGE_ME_smtp_pass
  external.api-key           = CHANGE_ME_sms_api_key

secret/gateway-service
  spring.datasource.url      = jdbc:postgresql://postgres:5432/gatewaydb
  spring.datasource.username = gateway_user
  spring.datasource.password = CHANGE_ME_gateway_db_pass
  jwt.secret                 = CHANGE_ME_jwt_256bit_key
```

---

## Update Secrets (replace CHANGE_ME values)

```powershell
# PowerShell — set up vault CLI
$env:VAULT_ADDR  = "http://localhost:8200"
$env:VAULT_TOKEN = (Get-Content vault\credentials\init.json | ConvertFrom-Json).root_token

# Update auth-service
vault kv put secret/auth-service `
  "spring.datasource.url=jdbc:postgresql://db:5432/authdb" `
  "spring.datasource.username=auth_user" `
  "spring.datasource.password=real_db_password" `
  "jwt.secret=real_256bit_jwt_secret" `
  "oauth2.client-secret=real_oauth_secret"

# Patch just one key (keeps all others unchanged)
vault kv patch secret/payment-service `
  "external.api-key=real_payment_api_key"
```

```bash
# Git Bash / WSL
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(grep root_token vault/credentials/init.json | sed 's/.*: *"\([^"]*\)".*/\1/')

vault kv put secret/e-kyc-service \
  "spring.datasource.password=real_pass" \
  "external.api-key=real_key"
```

---

## Vault CLI Reference

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(grep root_token vault/credentials/init.json | sed 's/.*: *"\([^"]*\)".*/\1/')

# Secrets
vault kv get secret/auth-service
vault kv get -field="spring.datasource.password" secret/auth-service
vault kv put secret/auth-service key=value key2=value2
vault kv patch secret/auth-service key=new_value
vault kv metadata get secret/auth-service        # version history
vault kv rollback -version=2 secret/auth-service # roll back

# AppRole
vault list auth/approle/role
vault read auth/approle/role/auth-service/role-id
vault write -f auth/approle/role/auth-service/secret-id   # new secret-id
vault write auth/approle/login role_id=X secret_id=Y      # test login

# Policies
vault policy list
vault policy read auth-service

# Status
vault status
vault secrets list
vault auth list
```

---

## How Spring Boot Loads Secrets

```
Startup
 └─▶ bootstrap.yml parsed
       └─▶ POST /v1/auth/approle/login
             (VAULT_ROLE_ID + VAULT_SECRET_ID → short-lived token)
             └─▶ GET /v1/secret/data/auth-service
                   (all key=value pairs fetched)
                   └─▶ Injected into Spring Environment
                         └─▶ ${spring.datasource.password} resolves
                               └─▶ DB pool starts → App ready ✓
```

### In code (Kotlin)

```kotlin
@Value("\${jwt.secret}")
private lateinit var jwtSecret: String

@ConfigurationProperties(prefix = "spring.datasource")
data class DbConfig(val url: String, val username: String, val password: String)
```

### Wire service container to Vault

```yaml
# microservices/auth-service/docker-compose.yml
services:
  auth-service:
    image: your-org/auth-service:latest
    env_file:
      - ../../vault/credentials/auth-service.env  # provides VAULT_ROLE_ID + VAULT_SECRET_ID
    environment:
      VAULT_HOST: vault
      VAULT_PORT: "8200"
    networks:
      - vault-net

networks:
  vault-net:
    external: true
```

---

## Add a New Microservice

```powershell
# 1. Register in Vault
$env:VAULT_ADDR  = "http://localhost:8200"
$env:VAULT_TOKEN = (Get-Content vault\credentials\init.json | ConvertFrom-Json).root_token
sh vault/scripts/add-service.sh order-service

# 2. Set real secrets
vault kv put secret/order-service `
  "spring.datasource.url=jdbc:postgresql://db:5432/orderdb" `
  "spring.datasource.password=real_pass"

# 3. Copy Spring Boot template
cp -r microservices/_template microservices/order-service
# Edit bootstrap.yml → replace MY_SERVICE_NAME with order-service
```

---

## Rotate AppRole Credentials

```powershell
$env:VAULT_ADDR  = "http://localhost:8200"
$env:VAULT_TOKEN = (Get-Content vault\credentials\init.json | ConvertFrom-Json).root_token
sh vault/scripts/rotate-secret-id.sh auth-service

# Restart the service to pick up new credentials
docker restart auth-service
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `permission denied /vault/data/core` | Named volume owned by root, vault user can't write | Fixed: `vault-permissions` container pre-chowns to uid 100 |
| `credentials/` empty after init | vault-init ran as non-root, can't write host folder | Fixed: `user: "0"` on vault-init in docker-compose |
| `Could not parse unseal_key` | wget JSON parsing of array failed | Fixed: uses vault CLI binary directly |
| vault UI shows init screen | vault-permissions container didn't finish before vault | Fixed: `depends_on: service_completed_successfully` |
| `vault-init` missing from `docker ps` | It exited — that's correct. Check: `docker logs vault-init` | `docker logs vault-init` |

### Full reset

```powershell
docker compose down -v
Remove-Item -Force -Recurse vault\credentials\* -ErrorAction SilentlyContinue
docker compose up -d
docker logs -f vault-init
```
# vault-setup
