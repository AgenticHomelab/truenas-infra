# TrueNAS Infrastructure

OpenTofu source for approved, stable infrastructure on a separate physical
TrueNAS system serving a Kubernetes homelab.

Three independent root modules define their own ownership:
- `acme/`: TrueNAS native API certificate and DNS authenticator metadata.
- `identities/`: selected stable service users, groups and privileges.
- `storage/`: stable datasets, static NFS exports, selected snapshot policies
  and deliberately adopted Cloud Backup task configuration.

The TrueNAS CSI driver and native applications retain ownership of mutable
PVC data and application credentials. Neither this source nor GitHub Actions
is authorized to discover or import arbitrary live TrueNAS objects.

## Private execution inputs

Approved private, noncredential input files are stored in the private
`AgenticHomelab/homelab-secrets` repository. These include the full
hostname-verified TrueNAS API endpoint, selected WebDAV metadata and an
existing backup source path. Use a protected operator checkout with native
OpenTofu `-var-file` where appropriate. See the
[private input contract](docs/private-publication-inputs.md) for each root.
See [adoption and state recovery](docs/adoption.md) for the existing backend
and storage ownership boundaries.

Existing stable service credentials remain authoritative in OCI Vault.
The Kubernetes CSI API key is delivered by ESO to its existing Kubernetes
Secret, under [Talos GitOps ownership](https://github.com/AgenticHomelab/talos-cluster/blob/main/kubernetes/infrastructure/truenas-csi/README.md).
The 2026-11-24 migration preserved the CSI credential bytes and Secret UID.
This does not change TrueNAS service identities, the OpenTofu provider keys,
backend selectors, or independently protected recovery credentials.

For an authorized source cutover, select the root's existing S3 credential
profile in the OpenTofu process and clear inherited AWS access-key overrides.
An ACME configuration without a stored profile can use the approved local
profile through `AWS_PROFILE`. First run `tofu state list` from the original
initialized root. Once that succeeds, reuse the original protected backend
configuration for the new checkout and verify the same state lineage and
resource addresses. Keep backend settings and state outside Git.

Each OpenTofu root retains its own independently protected OCI Object Storage
backend, state lineage and native lockfile. **Do not initialize against
production state, import, plan or apply** merely to verify publication.

The [Garage backup protection guide](docs/garage-backup.md) explains why
snapshots, encrypted copies and verified restoration are distinct controls.
There are two distinct Cloud Sync tasks: the BorgWarehouse task is declared
with `enabled = false`, while the separate Garage task uses the protected
`garage_offsite_enabled` input. Preserve the accepted Garage activation inputs;
public defaults do not establish either task's current live status.

## Validation and safety

Offline CI checks formatting, backend-free initialization, source validation
and synthetic native provider tests. It never proves actual NAS health,
remote-state recovery, or a no-change production plan. All such operational
checks require separately authorized access and a reviewed rollback plan.

This is the published, clean-history public TrueNAS desired-state source.
The operator workstation uses the public ACME and identities roots. The
authorized storage runner uses the public storage root. Each selected path
matched its original state and produced a locked, refreshing plan with zero
proposed changes. Apply requires separate authorization. The former private source is an archive of historical evidence, not a runtime
or recovery dependency. Use current Git history and independently protected
execution inputs for recovery.
Independent off-host restoration and Vaultwarden recovery retrieval remain
unverified.
