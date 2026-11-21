# Contributor and agent instructions

This repository is the published, clean-history **public desired-state
source** for approved TrueNAS infrastructure. Review current source and
relevant public runbooks before changes; default to read-only investigation.

- Use English for code, comments, and documentation; Conventional Commits.
- Use focused PRs; do not push directly to `main`.
- OpenTofu owns only adopted stable TrueNAS infrastructure. TrueNAS CSI owns
  PVC children; native applications own mutable state; Flux owns Kubernetes
  desired state; OCI OpenTofu and Ansible retain their separate owners.
- Preserve the existing independent, versioned OCI S3 state backends, locks,
  resource addresses and provider versions. Never import, apply, force-unlock,
  migrate state or rotate credentials without separate explicit authorization.
- Use synthetic offline tests. Never fetch real credentials or state from CI.
- Production-specific NAS URLs, private network inventories, WebDAV service
  usernames and CSI volume identities must not be committed to public source.
  Those noncredential inputs belong in the private
  `AgenticHomelab/homelab-secrets` source.
- OCI Vault remains authoritative for existing stable credentials. Keys,
  tokens, S3 credentials and independent recovery identities stay out of Git.
- Do not assert successful backup, deployment or restored runtime health from
  Git desired state or offline CI.
- The public source has been published after a separate clean-history review;
  this does not replace existing private production execution paths. A runtime
  source switch needs separately reviewed operator approval, complete approved
  protected inputs, exact original backends/locks, refreshed no-unexpected-change
  plans, and appropriate independent recovery and rollback.
