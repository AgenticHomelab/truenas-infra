output "api_hostname" {
  description = "Configured hostname for the native TrueNAS API certificate."
  value       = var.api_dns_name
}

output "managed_certificate_id" {
  description = "TrueNAS identifier for the ACME-managed certificate."
  value       = truenas_certificate.api_acme.id
}

output "certificate_expired" {
  description = "Whether the managed certificate is expired."
  value       = truenas_certificate.api_acme.expired
}
