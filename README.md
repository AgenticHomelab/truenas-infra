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
OpenTofu `-var-file` where appropriate.

Existing stable service credentials remain authoritative in OCI Vault;
protected runtime copies, provider key files, backend selectors and
independent recovery credentials are managed outside public Git.

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
snapshots, encrypted copies and verified restoration are distinct controls,
and why the offsite SYNC must remain separately gated.

## Validation and safety

Offline CI checks formatting, backend-free initialization, source validation
and synthetic native provider tests. It never proves actual NAS health,
remote-state recovery, or a no-change production plan. All such operational
checks require separately authorized access and a reviewed rollback plan.

The current source is a publication candidate, not release authorization.
Any new public repository must be initialized with a new history-free root
commit after complete content and metadata review. The existing private
repository and original operational evidence remain private.
