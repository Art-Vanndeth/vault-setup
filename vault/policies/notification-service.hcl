# Policy: notification-service
path "secret/data/notification-service" {
  capabilities = ["read"]
}
path "secret/metadata/notification-service" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
