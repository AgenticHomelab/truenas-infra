# Existing service identities only. Do not put private names, IDs or passwords
# in this repository. Supply reviewed live-equivalent values in ignored tfvars.

variable "service_users" {
  description = "Approved existing non-built-in TrueNAS service users, keyed by stable private aliases."
  type = map(object({
    username               = string
    full_name              = string
    email                  = optional(string)
    group_create           = optional(bool)
    uid                    = optional(number)
    group                  = optional(number)
    groups                 = optional(list(number))
    home                   = optional(string)
    home_mode              = optional(string)
    shell                  = optional(string)
    locked                 = optional(bool)
    password_disabled      = optional(bool)
    smb                    = optional(bool)
    ssh_password_enabled   = optional(bool)
    sshpubkey              = optional(string)
    sudo_commands          = optional(list(string))
    sudo_commands_nopasswd = optional(list(string))
    webshare               = optional(bool)
  }))
  nullable = false
}

resource "truenas_user" "service" {
  for_each = var.service_users

  username               = each.value.username
  full_name              = each.value.full_name
  email                  = each.value.email
  group_create           = each.value.group_create
  uid                    = each.value.uid
  group                  = each.value.group
  groups                 = each.value.groups
  home                   = each.value.home
  home_mode              = each.value.home_mode
  shell                  = each.value.shell
  locked                 = each.value.locked
  password_disabled      = each.value.password_disabled
  smb                    = each.value.smb
  ssh_password_enabled   = each.value.ssh_password_enabled
  sshpubkey              = each.value.sshpubkey
  sudo_commands          = each.value.sudo_commands
  sudo_commands_nopasswd = each.value.sudo_commands_nopasswd
  webshare               = each.value.webshare

  # Imported users retain existing password hashes and other native identity
  # state; never supply password or password_wo_version for adoption.
  lifecycle {
    prevent_destroy = true
  }
}

variable "service_groups" {
  description = "Existing local groups dedicated to the approved TrueNAS service identities."
  type = map(object({
    name = string
    gid  = optional(number)
    smb  = optional(bool)
  }))
  nullable = false
}

resource "truenas_group" "service" {
  for_each = var.service_groups

  name = each.value.name
  gid  = each.value.gid
  smb  = each.value.smb

  # Avoid managing group.users and user.groups simultaneously.
  lifecycle {
    prevent_destroy = true
  }
}

variable "service_privileges" {
  description = "Existing TrueNAS privileges and their exact current role and GID assignments."
  type = map(object({
    name         = string
    web_shell    = bool
    local_groups = list(number)
    ds_groups    = list(number)
    roles        = list(string)
  }))
  nullable = false
}

resource "truenas_privilege" "service" {
  for_each = var.service_privileges

  name         = each.value.name
  web_shell    = each.value.web_shell
  local_groups = each.value.local_groups
  ds_groups    = each.value.ds_groups
  roles        = each.value.roles

  lifecycle {
    prevent_destroy = true
  }
}

variable "service_api_keys" {
  description = "Existing TrueNAS API-key metadata; secret values are independently authoritative in OCI Vault."
  type = map(object({
    name       = string
    username   = string
    expires_at = optional(string)
  }))
  nullable = false
}

resource "truenas_api_key" "service" {
  for_each = var.service_api_keys

  name       = each.value.name
  username   = each.value.username
  expires_at = each.value.expires_at

  # Import never reads plaintext key values; it must not rotate credentials.
  lifecycle {
    prevent_destroy = true
  }
}
