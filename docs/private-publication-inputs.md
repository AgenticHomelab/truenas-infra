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
remain supplied independently. Preserve the approved Garage activation flags
and independently held crypt inputs as part of the complete storage inputs.
Do not log, commit or redistribute credential values. Sensitive provider
configuration, including the WebDAV credential, may be present in protected
state; sensitivity marking alone does not prevent persistence. The Garage
crypt password and salt use ephemeral inputs and write-only provider fields
instead. OCI Vault stays the authority for stable credentials. The private source does not trigger live reconciliation.

The operator workstation uses the public ACME and identities roots, and
Hermes uses the public storage root. Operator-reported acceptance confirmed
matching original backends and lineages and locked, refreshing no-change
plans for all three roots. Former private repositories are historical archives. Recover from current
repository history, original backend selectors and independently protected
inputs, not an old checkout.

Any future source switch requires complete private inputs, the existing
credential authorities and original backend and lock settings, with a
reviewed rollback and independent recovery path. Off-host restoration and
Vaultwarden recovery-copy retrieval remain unverified. Apply, import,
credential rotation and state migration require separate authorization.
