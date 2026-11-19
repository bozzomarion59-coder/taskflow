variable "ghcr_owner" {
  type        = string
  description = "Propriétaire des images sur ghcr.io"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.ghcr_owner))
    error_message = "ghcr_owner : minuscules, chiffres et tirets uniquement."
  }
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag des images : SHA court (7 hexadécimaux) ou latest"
  validation {
    condition     = var.image_tag == "latest" || can(regex("^[0-9a-f]{7}$", var.image_tag))
    error_message = "image_tag : un SHA court de 7 caractères hexadécimaux, ou latest."
  }
}

variable "front_port" {
  type    = number
  default = 8081
  validation {
    condition     = var.front_port >= 1024 && var.front_port <= 65535
    error_message = "front_port doit être compris entre 1024 et 65535."
  }
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "db_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Mot de passe de la base. Si null, un mot de passe aléatoire est généré."
}

variable "ghcr_username" {
  type    = string
  default = null
}

variable "ghcr_token" {
  type      = string
  default   = null
  sensitive = true
}
