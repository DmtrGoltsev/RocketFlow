variable "cloud_id" {
  description = "Yandex Cloud id."
  type        = string
}

variable "folder_id" {
  description = "Yandex Cloud folder id."
  type        = string
}

variable "project_name" {
  description = "Short project name used in resource names."
  type        = string
  default     = "rocketflow"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"
}

variable "zone" {
  description = "Yandex Cloud availability zone."
  type        = string
  default     = "ru-central1-a"
}

variable "subnet_cidr" {
  description = "CIDR block for the production subnet."
  type        = string
  default     = "10.42.0.0/24"
}

variable "api_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the backend HTTP port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach SSH. Keep empty to close SSH."
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Optional SSH public key for yc-user on the backend VM."
  type        = string
  default     = ""
}

variable "initial_container_image" {
  description = "Container image used for the first VM boot before CI/CD deploys the real backend image."
  type        = string
  default     = "cr.yandex/yc/demo/coi:v1"
}

variable "compute_platform_id" {
  description = "Compute platform id for the backend VM."
  type        = string
  default     = "standard-v3"
}

variable "compute_cores" {
  description = "Backend VM CPU cores."
  type        = number
  default     = 2
}

variable "compute_memory_gb" {
  description = "Backend VM memory in GB."
  type        = number
  default     = 2
}

variable "compute_disk_size_gb" {
  description = "Backend VM boot disk size in GB."
  type        = number
  default     = 20
}

variable "compute_disk_type_id" {
  description = "Backend VM boot disk type."
  type        = string
  default     = "network-ssd"
}

variable "postgresql_version" {
  description = "Managed PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "RocketFlow application database name."
  type        = string
  default     = "rocketflow"
}

variable "db_user" {
  description = "RocketFlow application database user."
  type        = string
  default     = "rocketflow_app"
}

variable "db_password" {
  description = "RocketFlow application database password. Terraform state will contain this value."
  type        = string
  sensitive   = true
}

variable "db_resource_preset_id" {
  description = "Managed PostgreSQL resource preset."
  type        = string
  default     = "s2.micro"
}

variable "db_disk_type_id" {
  description = "Managed PostgreSQL disk type."
  type        = string
  default     = "network-ssd"
}

variable "db_disk_size_gb" {
  description = "Managed PostgreSQL disk size in GB."
  type        = number
  default     = 20
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for the Managed PostgreSQL cluster."
  type        = bool
  default     = true
}
