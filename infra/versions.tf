terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend vide : le chemin du state est donné à l'init (-backend-config),
  # pour qu'il ne soit pas écrit en dur ni versionné.
  backend "local" {}
}
