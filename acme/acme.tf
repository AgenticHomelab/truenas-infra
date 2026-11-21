variable "cloudflare_dns_token" {
  description = "Zone-scoped Cloudflare API token supplied only at execution time."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "cloudflare_token_revision" {
  description = "Increment after replacing the Cloudflare DNS token."
  type        = number
  default     = 1

  validation {
    condition     = var.cloudflare_token_revision >= 1 && floor(var.cloudflare_token_revision) == var.cloudflare_token_revision
    error_message = "cloudflare_token_revision must be a positive integer."
  }
}

resource "truenas_acme_dns_authenticator" "cloudflare" {
  name = "truenas-csi-cloudflare-dns01"

  attributes = jsonencode({
    authenticator = "cloudflare"
  })

  # Keep the token out of state through the provider's write-only field.
  attributes_secrets_wo = jsonencode({
    api_token = var.cloudflare_dns_token
  })
  attributes_secrets_wo_version = var.cloudflare_token_revision

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_certificate" "api_csr" {
  name             = "truenas-csi-api-csr"
  create_type      = "CERTIFICATE_CREATE_CSR"
  common           = var.api_dns_name
  san              = [var.api_dns_name]
  key_type         = "EC"
  ec_curve         = "SECP256R1"
  store_privatekey = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_certificate" "api_acme" {
  name               = "truenas-csi-api-acme"
  create_type        = "CERTIFICATE_CREATE_ACME"
  acme_directory_uri = "https://acme-v02.api.letsencrypt.org/directory"
  csr_id             = truenas_certificate.api_csr.id
  dns_mapping = {
    (var.api_dns_name) = truenas_acme_dns_authenticator.cloudflare.id
  }
  tos        = true
  renew_days = 20

  lifecycle {
    prevent_destroy = true
  }
}
