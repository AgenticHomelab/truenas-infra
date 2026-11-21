terraform {
  required_version = ">= 1.11.0"

  required_providers {
    truenas = {
      source  = "truenas/truenas"
      version = "= 1.8.0"
    }
  }

  # The real backend is supplied through a local, ignored HCL file.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

variable "api_dns_name" {
  description = "Required fully qualified DNS name for the native TrueNAS API certificate."
  type        = string
  nullable    = false

  validation {
    condition = length(var.api_dns_name) <= 253 && can(regex(
      "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
      var.api_dns_name
    ))
    error_message = "api_dns_name must be a fully qualified DNS hostname."
  }
}

variable "truenas_ca_cert_path" {
  description = "Optional local path to a trusted TrueNAS certificate or CA bundle."
  type        = string
  default     = null
  nullable    = true
}

# Optional native inputs for a persistent, protected execution environment.
# Null preserves existing TRUENAS_ENDPOINT and TRUENAS_API_KEY fallback on the
# operator workstation. Never place API-key values in Git or local HCL.
variable "truenas_api_endpoint" {
  description = "Direct hostname-verified TrueNAS WSS endpoint; omit to use TRUENAS_ENDPOINT."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.truenas_api_endpoint == null ? true : startswith(var.truenas_api_endpoint, "wss://")
    error_message = "Use an HTTPS-verified wss:// TrueNAS API endpoint."
  }
}

variable "truenas_api_key_file" {
  description = "Absolute path to the execution identity's protected TrueNAS API key; omit to use TRUENAS_API_KEY."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.truenas_api_key_file == null ? true : startswith(var.truenas_api_key_file, "/")
    error_message = "Provide an absolute path to the protected TrueNAS API key."
  }
}

provider "truenas" {
  endpoint = var.truenas_api_endpoint
  api_key  = var.truenas_api_key_file == null ? null : trimspace(file(pathexpand(var.truenas_api_key_file)))
  ca_cert  = var.truenas_ca_cert_path
}
