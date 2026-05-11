# Policy: auth-service
path "secret/data/auth-service" {
  capabilities = ["read"]
}
path "secret/metadata/auth-service" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
