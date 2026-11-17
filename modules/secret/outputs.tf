output "id" {
  description = <<DESCRIPTION
The versioned data plane URI of the secret, in the form
`https://<vault-name>.vault.azure.net/secrets/<secret-name>/<secret-version>`.

Because it pins a specific secret version, consumers will not pick up new versions
automatically; use `versionless_id` instead if that is required.
DESCRIPTION
  value       = var.control_plane_enabled ? local.control_plane_output.secret_uri_with_version : azurerm_key_vault_secret.this[0].id
}

output "name" {
  description = "The name of the Key Vault Secret."
  value       = var.control_plane_enabled ? basename(azapi_resource_action.this[0].resource_id) : azurerm_key_vault_secret.this[0].name
}

output "resource_id" {
  description = <<DESCRIPTION
The versioned Azure Resource Manager (ARM) resource ID of the secret, in the form
`/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.KeyVault/vaults/<vault-name>/secrets/<secret-name>/versions/<secret-version>`.

This is an ARM resource ID, not a data plane URI. Use `id` when a service asks for a
key vault secret URI such as `https://<vault-name>.vault.azure.net/secrets/...`.
DESCRIPTION
  value       = var.control_plane_enabled ? "${local.resource_versionless_id}/versions/${basename(local.control_plane_output.secret_uri_with_version)}" : azurerm_key_vault_secret.this[0].resource_id
}

output "resource_versionless_id" {
  description = <<DESCRIPTION
The versionless Azure Resource Manager (ARM) resource ID of the secret, in the form
`/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.KeyVault/vaults/<vault-name>/secrets/<secret-name>`.

This is an ARM resource ID, not a data plane URI. Because it does not pin a secret
version, consumers that support it will pick up new secret versions automatically.
DESCRIPTION
  value       = local.resource_versionless_id
}

output "versionless_id" {
  description = <<DESCRIPTION
The versionless data plane URI of the secret, in the form
`https://<vault-name>.vault.azure.net/secrets/<secret-name>`.

Because it does not pin a secret version, consumers that support it will pick up new
secret versions automatically. Use `id` when a specific version is required.
DESCRIPTION
  value       = var.control_plane_enabled ? local.control_plane_output.secret_uri : azurerm_key_vault_secret.this[0].versionless_id
}
