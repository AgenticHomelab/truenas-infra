# Protection policy only: the native TrueNAS App retains ownership of the
# Garage dataset, configuration, identity, layout and mutable application data.
variable "garage_snapshot_enabled" {
  description = "Enable only after separate approval of the disabled task creation and snapshot activation plan."
  type        = bool
  default     = false
  nullable    = false
}

locals {
  garage_snapshot_tasks = {
    garage_backup = {
      dataset        = "tank/apps/garage"
      lifetime_unit  = "DAY"
      lifetime_value = 7
      naming_schema  = "garage-%Y-%m-%d_%H-%M"
      enabled        = var.garage_snapshot_enabled
      recursive      = false
      allow_empty    = true
      exclude        = []
      schedule = {
        minute = "35"
        hour   = "*"
        dom    = "*"
        month  = "*"
        dow    = "*"
        begin  = "00:00"
        end    = "23:59"
      }
    }
  }
}

# Content-encrypted offsite mirror of the Garage dataset. Disabled until activation is
# separately approved in docs/garage-backup.md. Reuses the existing Cloud
# Backup WebDAV credential by ID; creates no new credential or identity.

variable "garage_crypt_password" {
  description = "Dedicated rclone crypt password for the Garage offsite copy. Ephemeral, sensitive, never persisted in state or Git."
  type        = string
  sensitive   = true
  ephemeral   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.garage_crypt_password)) >= 32
    error_message = "Supply the approved Garage crypt password, at least 32 characters, from independent recovery custody."
  }
}

variable "garage_crypt_salt" {
  description = "Dedicated rclone crypt salt for the Garage offsite copy. Ephemeral, sensitive, never persisted in state or Git."
  type        = string
  sensitive   = true
  ephemeral   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.garage_crypt_salt)) >= 32
    error_message = "Supply the approved Garage crypt salt, at least 32 characters, from independent recovery custody."
  }
}

variable "garage_offsite_destination" {
  description = "Dedicated remote folder for the Garage copy, separate from BorgWarehouse."
  type        = string
  default     = "/backups/truenas/garage"
  nullable    = false

  validation {
    condition     = var.garage_offsite_destination == "/backups/truenas/garage"
    error_message = "Use the reviewed dedicated /backups/truenas/garage destination. A destination migration requires source review, not a private override."
  }
}

variable "garage_offsite_enabled" {
  description = "Enable only after separate approval of crypt custody, destination capacity and the first full transfer."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.garage_offsite_enabled || var.garage_snapshot_enabled
    error_message = "Enable and verify the Garage snapshot policy before separately enabling the Garage transfer."
  }
}

resource "truenas_cloudsync_task" "garage_offsite" {
  description = "Garage encrypted offsite copy"
  path        = "/mnt/tank/apps/garage"
  credentials = truenas_cloudsync_credentials.cloud_backup.id

  attributes = jsonencode({
    folder = var.garage_offsite_destination
  })

  # Successful SYNC removes source-absent WAL/SHM and blocks. It is not atomic:
  # interruption can leave a mixed image and overwrite the previous recovery point.
  direction     = "PUSH"
  transfer_mode = "SYNC"
  enabled       = var.garage_offsite_enabled

  # Offset from the existing 02:00 BorgWarehouse task and Garage native snapshot jitter.
  schedule = {
    minute = "20"
    hour   = "03"
    dom    = "*"
    month  = "*"
    dow    = "*"
  }

  # Keep native file paths visible; crypt still encrypts file contents.
  snapshot            = true
  encryption          = true
  filename_encryption = false

  # Write-only on the pinned provider; values never enter state.
  encryption_password   = var.garage_crypt_password
  encryption_salt       = var.garage_crypt_salt
  encryption_wo_version = 1

  include               = []
  exclude               = []
  follow_symlinks       = false
  create_empty_src_dirs = false
  transfers             = 4
  bwlimit               = []
  pre_script            = ""
  post_script           = ""

  lifecycle {
    prevent_destroy = true
  }
}
