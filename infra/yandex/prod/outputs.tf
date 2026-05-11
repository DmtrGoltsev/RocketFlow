output "registry_id" {
  description = "Yandex Container Registry id."
  value       = yandex_container_registry.backend.id
}

output "backend_repository" {
  description = "Backend container repository."
  value       = yandex_container_repository.backend.name
}

output "backend_instance_id" {
  description = "Backend Compute Cloud instance id."
  value       = yandex_compute_instance.backend.id
}

output "backend_instance_public_ip" {
  description = "Backend VM public IPv4 address."
  value       = yandex_compute_instance.backend.network_interface[0].nat_ip_address
}

output "postgresql_cluster_id" {
  description = "Managed PostgreSQL cluster id."
  value       = yandex_mdb_postgresql_cluster.main.id
}

output "postgresql_host_fqdn" {
  description = "Managed PostgreSQL primary host FQDN."
  value       = tolist(yandex_mdb_postgresql_cluster.main.host)[0].fqdn
}

output "rocketflow_db_url" {
  description = "JDBC URL for RocketFlow backend production database."
  value       = "jdbc:postgresql://${tolist(yandex_mdb_postgresql_cluster.main.host)[0].fqdn}:6432/${var.db_name}?ssl=true&sslmode=require"
}

output "deployer_service_account_id" {
  description = "GitHub Actions deployer service account id."
  value       = yandex_iam_service_account.deployer.id
}

output "backend_vm_service_account_id" {
  description = "Backend VM service account id."
  value       = yandex_iam_service_account.backend_vm.id
}

output "github_secret_names" {
  description = "Secrets expected by the GitHub Actions production deploy workflow."
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
