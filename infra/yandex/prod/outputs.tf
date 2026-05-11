output "registry_id" {
  description = "ID registry в Yandex Container Registry."
  value       = yandex_container_registry.backend.id
}

output "backend_repository" {
  description = "Репозиторий контейнеров backend."
  value       = yandex_container_repository.backend.name
}

output "backend_instance_id" {
  description = "ID инстанса Compute Cloud для backend."
  value       = yandex_compute_instance.backend.id
}

output "backend_instance_public_ip" {
  description = "Публичный IPv4-адрес backend VM."
  value       = yandex_compute_instance.backend.network_interface[0].nat_ip_address
}

output "postgresql_cluster_id" {
  description = "ID кластера Managed PostgreSQL."
  value       = yandex_mdb_postgresql_cluster.main.id
}

output "postgresql_host_fqdn" {
  description = "FQDN основного хоста Managed PostgreSQL."
  value       = tolist(yandex_mdb_postgresql_cluster.main.host)[0].fqdn
}

output "rocketflow_db_url" {
  description = "JDBC URL production-базы данных для backend RocketFlow."
  value       = "jdbc:postgresql://${tolist(yandex_mdb_postgresql_cluster.main.host)[0].fqdn}:6432/${var.db_name}?ssl=true&sslmode=require"
}

output "deployer_service_account_id" {
  description = "ID сервисного аккаунта deployer для GitHub Actions."
  value       = yandex_iam_service_account.deployer.id
}

output "backend_vm_service_account_id" {
  description = "ID сервисного аккаунта backend VM."
  value       = yandex_iam_service_account.backend_vm.id
}

output "github_secret_names" {
  description = "Secrets, которые ожидает workflow production-деплоя в GitHub Actions."
  value = [
    "YC_SERVICE_ACCOUNT_KEY_JSON",
    "YC_CLOUD_ID",
    "YC_FOLDER_ID",
    "YC_PROD_REGISTRY_ID",
    "YC_PROD_BACKEND_INSTANCE_ID",
    "ROCKETFLOW_PROD_DB_URL",
    "ROCKETFLOW_PROD_DB_USERNAME",
    "ROCKETFLOW_PROD_DB_PASSWORD"
  ]
}
