# Garage backup protection

This guide describes the reusable desired-state boundaries implemented in
`storage/garage_backup.tf`. It does not include private infrastructure
addresses, encryption material, recovery commands for a live system or
evidence of a successful production restoration.

## Ownership and safeguards

The native TrueNAS application owns the Garage configuration, SQLite
metadata, bucket identity, data layout and mutable application state.
OpenTofu declares only a bounded native snapshot policy and an optional
encrypted Cloud Sync task. Do not import the application's mutable dataset
or manage its lifecycle as a replaceable OpenTofu resource.

The additive `garage_backup` snapshot policy defaults to disabled and
uses `prevent_destroy`. Preserve the accepted protected activation inputs
when recovering an existing execution root; do not substitute public defaults. Existing snapshot-task maps must be supplied in
full from protected inputs: never replace the production map with an empty
or Garage-only map. The transfer has a *separate* enable switch and cannot
be enabled without the snapshot-policy switch.

## Crypt and offsite transfer

The Garage Cloud Sync task reuses the existing WebDAV credential by reference
but is separate from the BorgWarehouse task, which is declared disabled in
`storage/cloud_backup.tf`. The dedicated rclone
crypt password and salt are ephemeral, sensitive execution inputs; keep
them out of Git, OpenTofu state and application data exports. Retain them in
separate protected recovery custody that survives complete NAS loss.

The transfer is an encrypted PUSH with SYNC semantics. A completed SYNC
removes destination files absent from the source. It is **not atomic**:
an interrupted transfer can leave a mixed snapshot of SQLite metadata,
WAL/SHM files and data blocks, and can overwrite the previous offsite
recovery point. Content encryption does not make the copy transactionally
consistent; file paths may remain visible when filename encryption is off.

## Approval and verification gates

1. Confirm the original three independent OpenTofu S3 backend keys,
   native locks, state lineages, selected resource identities and complete
   protected root inputs. Offline validation is not proof of live equivalence.
2. Independently verify source ownership, destination access/capacity,
   encryption-key recovery custody and an isolated restore destination.
3. Require separately approved locked, refreshing plans before native
   snapshot creation or enabling offsite transfer. Do not run apply, import,
   state migration or force-unlock as part of source publication.
4. Stage the snapshot policy before considering the separate transfer
   activation. Inspect the complete plan and the unchanged existing task
   maps and credentials at each gate.
5. Require an independently checked, isolated restoration with application
   integrity validation before claiming the offsite copy is recoverable.
   Object replication, ZFS snapshots, encrypted copies and successful
   restorations are different assurance levels.

An unverified successful transfer is never proof of restoration safety.
Retain original data, native tasks, state and off-host recovery credentials
until a separately approved rollback and retirement plan is accepted.
