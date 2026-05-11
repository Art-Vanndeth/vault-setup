# Policy: payment-service
path "secret/data/payment-service" {
  capabilities = ["read"]
}
path "secret/metadata/payment-service" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
