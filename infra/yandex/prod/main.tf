locals {
  name_prefix = "${var.project_name}-${var.environment}"
  labels = {
    project     = var.project_name
    environment = var.environment
  }
}

resource "yandex_vpc_network" "main" {
  name   = "${local.name_prefix}-network"
  labels = local.labels
}

resource "yandex_vpc_subnet" "main" {
  name           = "${local.name_prefix}-subnet-${var.zone}"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
  labels         = local.labels
}

resource "yandex_vpc_security_group" "backend" {
  name       = "${local.name_prefix}-backend-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  ingress {
    description    = "Backend HTTP"
    protocol       = "TCP"
    port           = 8080
    v4_cidr_blocks = var.api_allowed_cidr_blocks
  }

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidr_blocks) > 0 ? [1] : []

    content {
      description    = "SSH"
      protocol       = "TCP"
      port           = 22
      v4_cidr_blocks = var.ssh_allowed_cidr_blocks
    }
  }

  egress {
    description    = "Allow outbound traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "postgres" {
  name       = "${local.name_prefix}-postgres-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  ingress {
    description    = "PostgreSQL from production subnet"
    protocol       = "TCP"
    port           = 6432
    v4_cidr_blocks = [var.subnet_cidr]
  }

  egress {
    description    = "Allow outbound traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_container_registry" "backend" {
  name   = "${local.name_prefix}-registry"
  labels = local.labels
}

resource "yandex_container_repository" "backend" {
  name = "${yandex_container_registry.backend.id}/rocketflow-backend"
}

resource "yandex_iam_service_account" "backend_vm" {
  name        = "${local.name_prefix}-backend-vm"
  description = "Runs the RocketFlow backend VM and pulls backend images."
}

resource "yandex_iam_service_account" "deployer" {
  name        = "${local.name_prefix}-github-deployer"
  description = "Used by GitHub Actions to push images and update the backend container."
}

resource "yandex_resourcemanager_folder_iam_member" "backend_vm_registry_puller" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.backend_vm.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "deployer_registry_pusher" {
  folder_id = var.folder_id
  role      = "container-registry.images.pusher"
  member    = "serviceAccount:${yandex_iam_service_account.deployer.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "deployer_registry_puller" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.deployer.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "deployer_compute_editor" {
  folder_id = var.folder_id
  role      = "compute.editor"
  member    = "serviceAccount:${yandex_iam_service_account.deployer.id}"
}

resource "yandex_mdb_postgresql_cluster" "main" {
  name                = "${local.name_prefix}-postgres"
  environment         = "PRODUCTION"
  network_id          = yandex_vpc_network.main.id
  security_group_ids  = [yandex_vpc_security_group.postgres.id]
  deletion_protection = var.db_deletion_protection

  config {
    version = var.postgresql_version

    resources {
      resource_preset_id = var.db_resource_preset_id
      disk_type_id       = var.db_disk_type_id
      disk_size          = var.db_disk_size_gb
    }
  }

  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.main.id
  }

  labels = local.labels
}

resource "yandex_mdb_postgresql_user" "app" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = var.db_user
  password   = var.db_password
}

resource "yandex_mdb_postgresql_database" "app" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = var.db_name
  owner      = yandex_mdb_postgresql_user.app.name
}

data "yandex_compute_image" "container_optimized_image" {
  family = "container-optimized-image"
}

resource "yandex_compute_instance" "backend" {
  name                      = "${local.name_prefix}-backend"
  platform_id               = var.compute_platform_id
  zone                      = var.zone
  service_account_id        = yandex_iam_service_account.backend_vm.id
  allow_stopping_for_update = true
  labels                    = local.labels

  resources {
    cores  = var.compute_cores
    memory = var.compute_memory_gb
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.container_optimized_image.id
      size     = var.compute_disk_size_gb
      type     = var.compute_disk_type_id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.backend.id]
  }

  metadata = merge(
    {
      docker-container-declaration = templatefile("${path.module}/templates/docker-container-declaration.yaml.tftpl", {
        image = var.initial_container_image
      })
    },
    var.ssh_public_key == "" ? {} : {
      ssh-keys = "yc-user:${var.ssh_public_key}"
    }
  )

  depends_on = [
    yandex_resourcemanager_folder_iam_member.backend_vm_registry_puller
  ]
}
