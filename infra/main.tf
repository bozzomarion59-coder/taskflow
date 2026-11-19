# Mot de passe aléatoire (sans caractères spéciaux : il finit dans une URL),
# sauf si db_password est fourni (cas de la migration : on reprend celui du volume existant).
resource "random_password" "db" {
  length  = 32
  special = false
}

locals {
  db_password = coalesce(var.db_password, random_password.db.result)
  prefix      = "taskflow-${var.environment}"
}

resource "docker_network" "this" {
  name = local.prefix
}

resource "docker_volume" "pgdata" {
  name = "${local.prefix}-pgdata"

  # Compose a pose des labels com.docker.compose.* : on les ignore pour ne pas recreer le volume
  lifecycle {
    ignore_changes = [labels]
  }
}

resource "docker_image" "db" {
  name         = "docker.io/library/postgres:16-alpine"
  keep_locally = true
}

resource "docker_image" "api" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-api:${var.image_tag}"
  keep_locally = true
}

resource "docker_image" "front" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-front:${var.image_tag}"
  keep_locally = true
}

resource "docker_container" "db" {
  name    = "${local.prefix}-db"
  image   = docker_image.db.image_id
  restart = "unless-stopped"
  wait    = true

  env = [
    "POSTGRES_USER=taskflow",
    "POSTGRES_PASSWORD=${local.db_password}",
    "POSTGRES_DB=taskflow",
  ]

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["db"]
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U taskflow -d taskflow"]
    interval = "10s"
    timeout  = "3s"
    retries  = 10
  }
}

resource "docker_container" "api" {
  name       = "${local.prefix}-api"
  image      = docker_image.api.image_id
  restart    = "unless-stopped"
  wait       = true
  depends_on = [docker_container.db]

  env = [
    "DATABASE_URL=postgres://taskflow:${local.db_password}@db:5432/taskflow",
    "APP_ENV=${var.environment}",
  ]

  # L'alias "api" est le nom utilisé par front/nginx.conf
  networks_advanced {
    name    = docker_network.this.name
    aliases = ["api"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1"]
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
    start_period = "10s"
  }
}

resource "docker_container" "front" {
  cpu_shares = 512
  name       = "${local.prefix}-front"
  image      = docker_image.front.image_id
  restart    = "unless-stopped"
  depends_on = [docker_container.api]

  networks_advanced {
    name = docker_network.this.name
  }

  ports {
    internal = 80
    external = var.front_port
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
    start_period = "5s"
    interval     = "10s"
    timeout      = "3s"
    retries      = 3
  }
}
