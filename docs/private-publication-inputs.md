# Private noncredential inputs for the public TrueNAS source

The TrueNAS resource implementation remains in this repository. Approved
production-specific endpoint and Cloud Backup values are held in the private
`AgenticHomelab/homelab-secrets` repository:

- `config/truenas/storage.tfvars`: `truenas_api_endpoint`,
  `cloud_backup_webdav_url`, `cloud_backup_webdav_user`,
  `borgwarehouse_source_path`.
- `config/truenas/identities.tfvars`: `truenas_api_endpoint`.

The ACME root already accepts its API hostname and protected provider endpoint
as runtime inputs. None of the three roots changes its OCI S3 backend,
resource address, provider version, or native lock policy here.

Example for an **explicitly authorized**, protected operator/runner checkout:

```sh
tofu -chdir=storage plan \
  -var-file=/approved/private/checkout/config/truenas/storage.tfvars
```

Existing complete protected root-specific tfvars, Vault-selected password,
API key files, independent S3 backend selectors and execution identities must
remain supplied independently. Do not log, commit, copy into state, or
redistribute those secret values. OCI Vault stays the authority for stable
credentials. The private source does not trigger live reconciliation.

The operator workstation uses the public ACME and identities roots, and
Hermes uses the public storage root. Operator-reported acceptance confirmed
matching original backends and lineages and locked, refreshing no-change
plans for all three roots. The original private source remains available for rollback.

Any future source switch requires complete private inputs, the existing
credential authorities and original backend and lock settings, with a
reviewed rollback and independent recovery path. Off-host restoration and
Vaultwarden recovery-copy retrieval remain unverified. Apply, import,
credential rotation and state migration require separate authorization.
