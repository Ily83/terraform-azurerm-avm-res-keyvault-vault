output "e" {
  description = "The RSA public exponent of the Key Vault Key. Use together with `n`, which carries the modulus. Empty for EC keys. `null` when `control_plane_enabled` is `true`, because Azure Resource Manager does not return the public key."
  value       = var.control_plane_enabled ? null : azurerm_key_vault_key.this[0].e
}

output "id" {
  description = <<DESCRIPTION
The versioned data plane URI of the key, in the form
`https://<vault-name>.vault.azure.net/keys/<key-name>/<key-version>`.

This is the value most Azure services expect when configuring a customer managed key,
for example the `transparent_data_encryption_key_vault_key_id` input of the
`Azure/avm-res-sql-server/azurerm` module. It pins a specific key version. Note that
supporting key rotation does not imply accepting a versionless URI — Azure SQL, for
example, requires this versioned form and is told to follow rotation by a separate
setting. Use `versionless_id` only where the consuming API documents that it accepts a
versionless URI.
DESCRIPTION
  value       = var.control_plane_enabled ? azapi_resource.this[0].output.properties.keyUriWithVersion : azurerm_key_vault_key.this[0].id
}

output "n" {
  description = "The RSA modulus of the Key Vault Key. Use together with `e`, which carries the public exponent. Empty for EC keys. `null` when `control_plane_enabled` is `true`, because Azure Resource Manager does not return the public key."
  value       = var.control_plane_enabled ? null : azurerm_key_vault_key.this[0].n
}

output "name" {
  description = "The name of the Key Vault Key."
  value       = var.control_plane_enabled ? azapi_resource.this[0].name : azurerm_key_vault_key.this[0].name
}

output "public_key_openssh" {
  description = "The OpenSSH encoded public key of the Key Vault Key. Empty for `P-256K` keys, which the provider does not derive a public key for. `null` when `control_plane_enabled` is `true`, because Azure Resource Manager does not return the public key."
  value       = var.control_plane_enabled ? null : azurerm_key_vault_key.this[0].public_key_openssh
}

output "public_key_pem" {
  description = "The PEM encoded public key of the Key Vault Key. Empty for `P-256K` keys, which the provider does not derive a public key for. `null` when `control_plane_enabled` is `true`, because Azure Resource Manager does not return the public key."
  value       = var.control_plane_enabled ? null : azurerm_key_vault_key.this[0].public_key_pem
}

output "release_policy_configured" {
  description = "Whether the key has a release policy configured. Always `false` when `control_plane_enabled` is `true`, which does not support release policies."
  value       = var.control_plane_enabled ? false : length(azurerm_key_vault_key.this[0].release_policy) > 0
}

output "resource_id" {
  description = <<DESCRIPTION
The versioned Azure Resource Manager (ARM) resource ID of the key, in the form
`/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.KeyVault/vaults/<vault-name>/keys/<key-name>/versions/<key-version>`.

This is an ARM resource ID, not a data plane URI. Use `id` when a service asks for a
key vault key URI or identifier such as `https://<vault-name>.vault.azure.net/keys/...`.
DESCRIPTION
  value       = var.control_plane_enabled ? "${azapi_resource.this[0].id}/versions/${basename(azapi_resource.this[0].output.properties.keyUriWithVersion)}" : azurerm_key_vault_key.this[0].resource_id
}

output "resource_versionless_id" {
  description = <<DESCRIPTION
The versionless Azure Resource Manager (ARM) resource ID of the key, in the form
`/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.KeyVault/vaults/<vault-name>/keys/<key-name>`.

This is an ARM resource ID, not a data plane URI. Because it does not pin a key version,
services that support it will pick up new key versions automatically.
DESCRIPTION
  value       = local.resource_versionless_id
}

output "versionless_id" {
  description = <<DESCRIPTION
The versionless data plane URI of the key, in the form
`https://<vault-name>.vault.azure.net/keys/<key-name>`.

Because it does not pin a key version, services that support it will pick up new key
versions automatically. Use `id` when a service requires a specific key version.
DESCRIPTION
  value       = var.control_plane_enabled ? azapi_resource.this[0].output.properties.keyUri : azurerm_key_vault_key.this[0].versionless_id
}

output "x" {
  description = "The EC X component of the Key Vault Key. Use together with `y`, which carries the Y component. Empty for RSA keys. `null` when `control_plane_enabled` is `true`, because Azure Resource Manager does not return the public key."
  value       = var.control_plane_enabled ? null : azurerm_key_vault_key.this[0].x
}

output "y" {
  description = "The EC Y component of the Key Vault Key. Use together with `x`, which carries the X component. Empty for RSA keys. `null` when `control_plane_enabled` is `true`, because Azure Resource Manager does not return the public key."
  value       = var.control_plane_enabled ? null : azurerm_key_vault_key.this[0].y
}
