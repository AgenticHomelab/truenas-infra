# Offline only: the native mock never connects to TrueNAS or a backend.
mock_provider "truenas" {}

variables {
  datasets                     = {}
  static_nfs_exports           = {}
  snapshot_tasks               = {}
  truenas_api_key_file         = "/dev/null"
  truenas_api_endpoint         = "wss://nas.example.invalid/api/current"
  cloud_backup_webdav_url      = "https://backup.example.invalid/remote.php/dav/files/test/"
  cloud_backup_webdav_user     = "fixture-user"
  borgwarehouse_source_path   = "/mnt/fixture/csi-source"
  cloud_backup_webdav_password = format("%s-%s", "offline", "test-only")
  garage_crypt_password        = join("-", ["offline", "only", "do", "not", "use", "crypt", "password"])
  garage_crypt_salt            = join("-", ["offline", "only", "do", "not", "use", "crypt", "salt"])
}

run "garage_snapshot_is_additive" {
  command = plan

  assert {
    condition = (
      length(truenas_periodic_snapshot_task.selected) == 1 &&
      !truenas_periodic_snapshot_task.selected["garage_backup"].enabled
    )
    error_message = "The additive native Garage snapshot policy must default to disabled without replacing private input maps."
  }
}

run "reject_shadowed_garage_policy" {
  command = plan

  variables {
    snapshot_tasks = {
      garage_backup = {
        dataset        = "test/never-used"
        lifetime_unit  = "DAY"
        lifetime_value = 1
        naming_schema  = "test-%Y-%m-%d_%H-%M"
        enabled        = false
        recursive      = false
        schedule = {
          minute = "0"
          hour   = "0"
          dom    = "*"
          month  = "*"
          dow    = "*"
        }
      }
    }
  }

  expect_failures = [var.snapshot_tasks]
}

run "offsite_task_reuses_credential_and_disabled" {
  command = plan

  assert {
    condition = alltrue([
      truenas_cloudsync_task.garage_offsite.enabled == false,
      truenas_cloudsync_task.garage_offsite.direction == "PUSH",
      truenas_cloudsync_task.garage_offsite.transfer_mode == "SYNC",
      truenas_cloudsync_task.garage_offsite.snapshot == true,
      truenas_cloudsync_task.garage_offsite.encryption == true,
      truenas_cloudsync_task.garage_offsite.filename_encryption == false,
      truenas_cloudsync_task.garage_offsite.credentials == truenas_cloudsync_credentials.cloud_backup.id,
      jsondecode(truenas_cloudsync_task.garage_offsite.attributes).folder == "/backups/truenas/garage",
      truenas_cloudsync_task.garage_offsite.encryption_wo_version == 1,
      truenas_cloudsync_task.garage_offsite.schedule.minute == "20",
      truenas_cloudsync_task.garage_offsite.schedule.hour == "03",
      truenas_cloudsync_task.garage_offsite.schedule.dom == "*",
      truenas_cloudsync_task.garage_offsite.schedule.month == "*",
      truenas_cloudsync_task.garage_offsite.schedule.dow == "*",
    ])
    error_message = "The Garage offsite task must be disabled PUSH/SYNC with a source snapshot, content encryption, visible filenames, the fixed destination and existing Cloud Backup credential/write-only crypt version."
  }
}

run "reject_empty_crypt_password" {
  command = plan
  variables { garage_crypt_password = "" }
  expect_failures = [var.garage_crypt_password]
}

run "reject_empty_crypt_salt" {
  command = plan
  variables { garage_crypt_salt = "" }
  expect_failures = [var.garage_crypt_salt]
}

run "reject_borgwarehouse_destination" {
  command = plan
  variables { garage_offsite_destination = "/backups/truenas/borgwarehouse" }
  expect_failures = [var.garage_offsite_destination]
}

run "snapshot_only_activation" {
  command = plan
  variables { garage_snapshot_enabled = true }
  assert {
    condition = (
      truenas_periodic_snapshot_task.selected["garage_backup"].enabled &&
      !truenas_cloudsync_task.garage_offsite.enabled
    )
    error_message = "Explicit snapshot activation must not also activate the transfer."
  }
}

run "explicit_transfer_activation" {
  command = plan
  variables {
    garage_snapshot_enabled = true
    garage_offsite_enabled  = true
  }
  assert {
    condition = (
      truenas_cloudsync_task.garage_offsite.enabled &&
      truenas_periodic_snapshot_task.selected["garage_backup"].enabled &&
      !truenas_cloudsync_task.cloud_backup.enabled
    )
    error_message = "The separately approved transfer activation input must enable only the Garage task."
  }
}

run "reject_transfer_before_snapshot_policy" {
  command = plan
  variables {
    garage_snapshot_enabled = false
    garage_offsite_enabled  = true
  }
  expect_failures = [var.garage_offsite_enabled]
}

run "preserve_complete_existing_maps_and_policy" {
  command = plan
  variables {
    datasets = { existing = { name = "fixture/existing" } }
    static_nfs_exports = {
      existing = {
        path     = "/mnt/fixture/existing"
        enabled  = true
        ro       = true
        hosts    = []
        networks = []
        security = ["SYS"]
      }
    }
    snapshot_tasks = {
      existing = {
        dataset        = "fixture/existing"
        lifetime_unit  = "WEEK"
        lifetime_value = 4
        naming_schema  = "original-%Y-%m-%d_%H-%M"
        enabled        = true
        recursive      = true
        allow_empty    = false
        exclude        = ["fixture/existing/excluded"]
        schedule = {
          minute = "0"
          hour   = "2"
          dom    = "*"
          month  = "*"
          dow    = "*"
          begin  = "00:00"
          end    = "23:59"
        }
      }
    }
  }
  assert {
    condition = alltrue([
      length(truenas_dataset.stable) == 1,
      truenas_dataset.stable["existing"].name == "fixture/existing",
      !truenas_dataset.stable["existing"].force_destroy,
      length(truenas_nfs_share.static) == 1,
      truenas_nfs_share.static["existing"].path == "/mnt/fixture/existing",
      truenas_nfs_share.static["existing"].enabled,
      truenas_nfs_share.static["existing"].ro,
      length(truenas_nfs_share.static["existing"].hosts) == 0,
      length(truenas_nfs_share.static["existing"].networks) == 0,
      truenas_nfs_share.static["existing"].security == tolist(["SYS"]),
      length(truenas_periodic_snapshot_task.selected) == 2,
      truenas_periodic_snapshot_task.selected["existing"].dataset == "fixture/existing",
      truenas_periodic_snapshot_task.selected["existing"].lifetime_unit == "WEEK",
      truenas_periodic_snapshot_task.selected["existing"].lifetime_value == 4,
      truenas_periodic_snapshot_task.selected["existing"].naming_schema == "original-%Y-%m-%d_%H-%M",
      truenas_periodic_snapshot_task.selected["existing"].enabled,
      truenas_periodic_snapshot_task.selected["existing"].recursive,
      !truenas_periodic_snapshot_task.selected["existing"].allow_empty,
      truenas_periodic_snapshot_task.selected["existing"].exclude == tolist(["fixture/existing/excluded"]),
      truenas_periodic_snapshot_task.selected["existing"].schedule == var.snapshot_tasks["existing"].schedule,
      truenas_periodic_snapshot_task.selected["existing"].schedule.hour == "2",
      truenas_periodic_snapshot_task.selected["garage_backup"].dataset == "tank/apps/garage",
      truenas_periodic_snapshot_task.selected["garage_backup"].lifetime_unit == "DAY",
      truenas_periodic_snapshot_task.selected["garage_backup"].lifetime_value == 7,
      !truenas_periodic_snapshot_task.selected["garage_backup"].recursive,
      truenas_periodic_snapshot_task.selected["garage_backup"].allow_empty,
      truenas_periodic_snapshot_task.selected["garage_backup"].schedule.minute == "35",
      truenas_periodic_snapshot_task.selected["garage_backup"].schedule.hour == "*",
      truenas_cloudsync_task.cloud_backup.transfer_mode == "SYNC",
      !truenas_cloudsync_task.cloud_backup.enabled,
      truenas_cloudsync_task.cloud_backup.direction == "PUSH",
      truenas_cloudsync_task.cloud_backup.snapshot,
      truenas_cloudsync_task.cloud_backup.encryption,
      !truenas_cloudsync_task.cloud_backup.filename_encryption,
      jsondecode(truenas_cloudsync_task.cloud_backup.attributes).folder == "/backups/truenas/borgwarehouse",
      truenas_cloudsync_task.garage_offsite.path == "/mnt/tank/apps/garage",
      length(truenas_cloudsync_task.garage_offsite.include) == 0,
      length(truenas_cloudsync_task.garage_offsite.exclude) == 0,
      !truenas_cloudsync_task.garage_offsite.follow_symlinks,
      !truenas_cloudsync_task.garage_offsite.create_empty_src_dirs,
      truenas_cloudsync_task.garage_offsite.transfers == 4,
      length(truenas_cloudsync_task.garage_offsite.bwlimit) == 0,
      truenas_cloudsync_task.garage_offsite.pre_script == "",
      truenas_cloudsync_task.garage_offsite.post_script == "",
    ])
    error_message = "The Garage addition must preserve existing maps, backup task, complete source coverage and the reviewed snapshot policy."
  }
}
