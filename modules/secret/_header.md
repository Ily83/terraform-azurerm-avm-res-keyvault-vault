# terraform-azurerm-avm-res-keyvault-vault//secret

Module to deploy key vault secrets in Azure.

## Usage

This sub-module can be called directly to add secrets to an existing key vault:

Telemetry is enabled by default and requires `location`. Existing direct callers upgrading from
versions that did not have this input must provide it or set `enable_telemetry = false`.

```terraform
module "keyvault_secret" {
  source  = "Azure/avm-res-keyvault-vault/azurerm//modules/secret"
  version = "0.#.#" # Replace with your desired version

  key_vault_resource_id = azurerm_key_vault.this.id
  location              = azurerm_key_vault.this.location
  name                  = "my-secret"
  value                 = "my-secret-value"

  # Optional
  content_type = "text/plain"
  tags = {
    environment = "prod"
  }
  role_assignments = {
    secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = data.azurerm_client_config.this.object_id
    }
  }
}
```

## Creating the secret through Azure Resource Manager

Set `control_plane_enabled = true` to create the secret through Azure Resource Manager
(`Microsoft.KeyVault/vaults/secrets`) instead of the Key Vault data plane. The identity running
Terraform then needs `Microsoft.KeyVault/vaults/secrets/write` and `read` (for example Key Vault
Contributor) instead of a data plane role, and does not need network access to the vault: Azure
Resource Manager writes the secret even when the vault firewall denies by default. The default is
`false`, which keeps the data plane behaviour.

```terraform
module "keyvault_secret" {
  source  = "Azure/avm-res-keyvault-vault/azurerm//modules/secret"
  version = "0.#.#" # Replace with your desired version

  key_vault_resource_id = azapi_resource.key_vault.id
  location              = azapi_resource.key_vault.location
  name                  = "my-secret"
  control_plane_enabled = true
  value_wo              = ephemeral.random_password.this.result
  value_wo_version      = 1
}
```

Azure Resource Manager has no delete operation for secrets, so the module writes the secret with an
AzAPI PUT action (`azapi_resource_action`) rather than managing it as a resource:

- Removing the module, renaming the secret, setting `control_plane_enabled` back to `false` or
  running `terraform destroy` only removes the secret from the state. It stays in the vault until it
  is deleted through the data plane (for example `az keyvault secret delete`) or the vault is deleted.
- Terraform does not track the secret after writing it. A change made outside Terraform to its value,
  content type, dates or tags is neither detected nor reverted. Only the secret's URIs are read on
  every plan, so the outputs follow a version created outside Terraform.
- The value is sent in the AzAPI `sensitive_body`, a write-only argument, so it is kept out of the
  state, and also out of the plan when it comes from the ephemeral `value_wo`. Azure Resource Manager
  never returns it.
- The value is sent on creation, when `value_wo_version` changes, and with any change to the content
  type, dates or tags. A change of `value` or `value_wo` alone is not sent until `value_wo_version`
  changes. A `null` version counts as `0`.
- Switching an existing data plane secret to the control plane would first delete it through the
  data plane. Remove `azurerm_key_vault_secret.this[0]` from the state before applying instead, as
  the root module's README describes.
