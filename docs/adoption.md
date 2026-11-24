# TrueNAS adoption and state recovery

Use the three roots in this repository and the protected inputs described in
[the private input contract](private-publication-inputs.md). The operator runs
ACME and identities. The approved Hermes workspace runs storage. Each root
keeps its original versioned OCI S3 backend, state key and native lock.
The backend and full variables come from operator or runner custody.

## Recover an existing execution root

1. Identify the selected root, its expected addresses and its original backend
   from the protected operator inventory. Retrieve the root's original S3
   selector and credentials independently of the failed host. Use the approved
   process-scoped AWS profile and clear inherited credential and workspace
   overrides. Keep backend configuration and state outside public Git.
2. Supply the complete approved private map and the root's designated provider
   key with hostname verification. ACME also needs its original DNS token.
   Storage needs the existing Cloud Backup and Garage inputs when those resources
   are managed. The private overlays supplement the full maps.
3. In a separate recovery scope, verify the original backend identity, lineage,
   serial, addresses and lock policy before accepting the workspace. Stop on
   a missing state or lock error. Review existing object versions with the
   operator before any state restoration. Never initialize a replacement state
   or import resources to compensate for missing credentials or selectors.
4. If an authorized operator later requests a refreshing plan, use native
   locking and review the entire result. Keep raw state and plans protected.
   A state read or offline test establishes no application restore result.

## Scope of future additions

ACME metadata, adopted service identities, stable datasets and static exports,
and specifically adopted native protection tasks belong to these roots.
The existing CSI parent and its previously accepted service privilege are
already in place. Keep the complete input maps and existing state addresses.
The CSI driver retains ownership of its per-PVC datasets and exports. ESO
synchronizes the existing Kubernetes CSI API Secret from OCI Vault; that
consumer copy is not owned by these roots. Native applications retain their
own data, native mutable credentials and lifecycle.

For an explicitly approved additional parent, identify the exact existing
ancestor and confirm encryption inheritance, owner identity, backup coverage
and the absence of a conflicting dataset or export. Review a single-addition
plan with no unrelated changes before requesting approval to apply. Verify the
effective properties and existing dataset and export inventory afterwards.
Provision workloads and CSI claims through their owning GitOps source.

A TrueNAS-native snapshot task is a separate resource from the datasets and
snapshots it covers, including any descendants provisioned by CSI. Review
the complete task scope, recursion and exclusions, schedule, naming schema,
retention, overlap with adjacent policies and replication dependencies.
Verify observed scheduled snapshots separately before retiring coverage.
An import of an already existing task requires its own approval, original
state and native lock, exact task identity, preservation of the complete
map, and a subsequent locked no-change plan. A future task adoption does
not authorize changes to actual snapshots or CSI children.

Use the provider key selected for the root. Hermes fleet monitoring uses
its separate credential only for the documented read operations. See the
[Garage guide](garage-backup.md) for the retained Cloud Sync and recovery
boundaries.
