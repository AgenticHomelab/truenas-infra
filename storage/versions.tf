terraform {
  required_version = ">= 1.11.0"

  required_providers {
    truenas = {
      source  = "truenas/truenas"
      version = "= 1.8.0"
    }
  }

  # Supply the storage root's distinct private S3 state key outside Git.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

variable "truenas_ca_cert_path" {
  description = "Optional path to a locally trusted CA or server certificate bundle."
  type        = string
  default     = null
  nullable    = true
}

variable "truenas_api_endpoint" {
  description = "Hostname-verified production WSS endpoint supplied from the private noncredential configuration."
  type        = string
  nullable    = false

  validation {
    condition     = startswith(var.truenas_api_endpoint, "wss://")
    error_message = "Use a hostname-verified wss:// TrueNAS API endpoint."
  }
}

variable "truenas_api_key_file" {
  description = "Path to the protected API key for the execution identity."
  type        = string
  nullable    = false
}

provider "truenas" {
  endpoint = var.truenas_api_endpoint
  api_key  = trimspace(file(pathexpand(var.truenas_api_key_file)))
  ca_cert  = var.truenas_ca_cert_path
}
