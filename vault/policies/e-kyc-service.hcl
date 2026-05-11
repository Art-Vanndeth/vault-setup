# Policy: e-kyc-service
path "secret/data/e-kyc-service" {
  capabilities = ["read"]
}
path "secret/metadata/e-kyc-service" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
