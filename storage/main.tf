# Only explicitly approved, stable NAS infrastructure. CSI-generated PVC
# child datasets and NFS shares must never appear in any input map.

variable "datasets" {
  description = "Existing stable parent/static ZFS filesystems verified to be outside CSI ownership."
  type = map(object({
    name                     = string
    comments                 = optional(string)
    compression              = optional(string)
    checksum                 = optional(string)
    copies                   = optional(number)
    dedup                    = optional(string)
    acltype                  = optional(string)
    aclmode                  = optional(string)
    atime                    = optional(string)
    snapdir                  = optional(string)
    exec                     = optional(string)
    readonly                 = optional(string)
    recordsize               = optional(string)
    sync                     = optional(string)
    reservation              = optional(number)
    refreservation           = optional(number)
    special_small_block_size = optional(number)
    quota                    = optional(number)
    refquota                 = optional(number)
    # Encryption inputs are intentionally excluded: never replace encrypted datasets.
  }))
  nullable = false
}

resource "truenas_dataset" "stable" {
  for_each = var.datasets

  name                     = each.value.name
  comments                 = each.value.comments
  compression              = each.value.compression
  checksum                 = each.value.checksum
  copies                   = each.value.copies
  dedup                    = each.value.dedup
  acltype                  = each.value.acltype
  aclmode                  = each.value.aclmode
  atime                    = each.value.atime
  snapdir                  = each.value.snapdir
  exec                     = each.value.exec
  readonly                 = each.value.readonly
  recordsize               = each.value.recordsize
  sync                     = each.value.sync
  reservation              = each.value.reservation
  refreservation           = each.value.refreservation
  special_small_block_size = each.value.special_small_block_size
  quota                    = each.value.quota
  refquota                 = each.value.refquota
  force_destroy            = false

  # Force recursive deletion is never enabled for production/adopted datasets.
  # Dataset rename and replacement need separately reviewed recovery planning.
  lifecycle {
    prevent_destroy = true
  }
}

variable "static_nfs_exports" {
  description = "Existing dedicated/static NFS exports only, including the Longhorn backup target if verified."
  type = map(object({
    path             = string
    enabled          = bool
    ro               = bool
    hosts            = list(string)
    networks         = list(string)
    security         = list(string)
    comment          = optional(string)
    mapall_user      = optional(string)
    mapall_group     = optional(string)
    maproot_user     = optional(string)
    maproot_group    = optional(string)
    expose_snapshots = optional(bool)
  }))
  nullable = false
}

resource "truenas_nfs_share" "static" {
  for_each = var.static_nfs_exports

  path             = each.value.path
  enabled          = each.value.enabled
  ro               = each.value.ro
  hosts            = each.value.hosts
  networks         = each.value.networks
  security         = each.value.security
  comment          = each.value.comment
  mapall_user      = each.value.mapall_user
  mapall_group     = each.value.mapall_group
  maproot_user     = each.value.maproot_user
  maproot_group    = each.value.maproot_group
  expose_snapshots = each.value.expose_snapshots

  # NFS export optional fields are not safe to guess: omissions can reset
  # effective permissions. Populate exact API-observed values before import.
  lifecycle {
    prevent_destroy = true
  }
}

variable "snapshot_tasks" {
  description = "Only verified, separately owned native snapshot tasks, excluding unsafe CSI subtree coverage."
  type = map(object({
    dataset        = string
    lifetime_unit  = string
    lifetime_value = number
    naming_schema  = string
    enabled        = bool
    recursive      = bool
    allow_empty    = optional(bool)
    exclude        = optional(list(string))
    schedule = object({
      minute = string
      hour   = string
      dom    = string
      month  = string
      dow    = string
      begin  = optional(string)
      end    = optional(string)
    })
  }))
  nullable = false

  validation {
    condition     = !contains(keys(var.snapshot_tasks), "garage_backup")
    error_message = "garage_backup is a reserved additive policy key; preserve the complete existing snapshot_tasks map without overriding it."
  }
}

resource "truenas_periodic_snapshot_task" "selected" {
  # Reserved policy entries are additive to the complete protected live map.
  # Never replace that map with a Garage-only map.
  for_each = merge(var.snapshot_tasks, local.garage_snapshot_tasks)

  dataset        = each.value.dataset
  lifetime_unit  = each.value.lifetime_unit
  lifetime_value = each.value.lifetime_value
  naming_schema  = each.value.naming_schema
  enabled        = each.value.enabled
  recursive      = each.value.recursive
  allow_empty    = each.value.allow_empty
  exclude        = each.value.exclude

  schedule = each.value.schedule

  lifecycle {
    prevent_destroy = true
  }
}
