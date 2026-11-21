# Cloud Sync owns the backup task only. The CSI driver owns the source
# dataset and its lifecycle; do not declare or import that dataset here.

# Noncredential endpoint metadata is read from a private, reviewed tfvars file.
variable "cloud_backup_webdav_url" {
  type        = string
  description = "Private WebDAV service URL."
  nullable    = false
}

variable "cloud_backup_webdav_user" {
  type        = string
  description = "Private WebDAV service username."
  nullable    = false
}

variable "borgwarehouse_source_path" {
  type        = string
  description = "Existing CSI-owned BorgWarehouse source dataset path; not owned by this root."
  nullable    = false
}

variable "cloud_backup_webdav_password" {
  description = "Current Cloud Backup WebDAV application password, retrieved from OCI Vault at runtime."
  type        = string
  sensitive   = true
  nullable    = false
}

resource "truenas_cloudsync_credentials" "cloud_backup" {
  name = "Cloud Backup"

  provider_config = jsonencode({
    type   = "WEBDAV"
    vendor = "NEXTCLOUD"
    url    = var.cloud_backup_webdav_url
    user   = var.cloud_backup_webdav_user
    pass   = var.cloud_backup_webdav_password
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_cloudsync_task" "cloud_backup" {
  description = "BorgWarehouse CSI offsite backup"
  path        = var.borgwarehouse_source_path
  credentials = truenas_cloudsync_credentials.cloud_backup.id

  attributes = jsonencode({
    folder = "/backups/truenas/borgwarehouse"
  })

  direction     = "PUSH"
  transfer_mode = "SYNC"
  enabled       = false

  schedule = {
    minute = "0"
    hour   = "02"
    dom    = "*"
    month  = "*"
    dow    = "*"
  }

  snapshot              = true
  encryption            = true
  filename_encryption   = false
  include               = []
  exclude               = []
  follow_symlinks       = false
  create_empty_src_dirs = false
  transfers             = 4
  bwlimit               = []
  pre_script            = ""
  post_script           = ""

  # The existing rclone crypt password and salt stay on TrueNAS. Do not set
  # encryption_password, encryption_salt or encryption_wo_version on import.
  lifecycle {
    prevent_destroy = true
  }
}
