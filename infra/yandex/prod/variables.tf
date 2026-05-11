variable "cloud_id" {
  description = "ID облака Yandex Cloud."
  type        = string
}

variable "folder_id" {
  description = "ID каталога Yandex Cloud."
  type        = string
}

variable "project_name" {
  description = "Короткое имя проекта для имен ресурсов."
  type        = string
  default     = "rocketflow"
}

variable "environment" {
  description = "Имя окружения развертывания."
  type        = string
  default     = "prod"
}

variable "zone" {
  description = "Зона доступности Yandex Cloud."
  type        = string
  default     = "ru-central1-a"
}

variable "subnet_cidr" {
  description = "CIDR-блок production-подсети."
  type        = string
  default     = "10.42.0.0/24"
}

variable "api_allowed_cidr_blocks" {
  description = "CIDR-блоки, которым разрешен доступ к HTTP-порту backend."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR-блоки, которым разрешен SSH. Оставьте пустым, чтобы закрыть SSH."
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Опциональный публичный SSH-ключ для yc-user на backend VM."
  type        = string
  default     = ""
}

variable "initial_container_image" {
  description = "Container image для первого запуска VM до того, как CI/CD развернет настоящий образ backend."
  type        = string
  default     = "cr.yandex/yc/demo/coi:v1"
}

variable "compute_platform_id" {
  description = "ID compute platform для backend VM."
  type        = string
  default     = "standard-v3"
}

variable "compute_cores" {
  description = "Количество CPU-ядер для backend VM."
  type        = number
  default     = 2
}

variable "compute_memory_gb" {
  description = "Память backend VM в ГБ."
  type        = number
  default     = 2
}

variable "compute_disk_size_gb" {
  description = "Размер boot disk backend VM в ГБ."
  type        = number
  default     = 20
}

variable "compute_disk_type_id" {
  description = "Тип boot disk backend VM."
  type        = string
  default     = "network-ssd"
}

variable "postgresql_version" {
  description = "Основная версия Managed PostgreSQL."
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Имя базы данных приложения RocketFlow."
  type        = string
  default     = "rocketflow"
}

variable "db_user" {
  description = "Пользователь базы данных приложения RocketFlow."
  type        = string
  default     = "rocketflow_app"
}

variable "db_password" {
  description = "Пароль базы данных приложения RocketFlow. Terraform state будет содержать это значение."
  type        = string
  sensitive   = true
}

variable "db_resource_preset_id" {
  description = "Профиль ресурсов Managed PostgreSQL."
  type        = string
  default     = "s2.micro"
}

variable "db_disk_type_id" {
  description = "Тип диска Managed PostgreSQL."
  type        = string
  default     = "network-ssd"
}

variable "db_disk_size_gb" {
  description = "Размер диска Managed PostgreSQL в ГБ."
  type        = number
  default     = 20
}

variable "db_deletion_protection" {
  description = "Включить deletion protection для кластера Managed PostgreSQL."
  type        = bool
  default     = true
}
