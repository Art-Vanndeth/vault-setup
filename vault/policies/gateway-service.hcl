# Policy: gateway-service
path "secret/data/gateway-service" {
  capabilities = ["read"]
}
path "secret/metadata/gateway-service" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
