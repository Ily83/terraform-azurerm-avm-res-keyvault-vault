# terraform-azurerm-avm-res-keyvault-vault//key

Module to deploy key vault keys.

## Usage

This sub-module can be called directly to add keys to an existing key vault:

Telemetry is enabled by default and requires `location`. Existing direct callers upgrading from
versions that did not have this input must provide it or set `enable_telemetry = false`.

```terraform
module "keyvault_key" {
  source  = "Azure/avm-res-keyvault-vault/azurerm//modules/key"
  version = "0.#.#" # Replace with your desired version

  key_vault_resource_id = azurerm_key_vault.this.id
  location              = azurerm_key_vault.this.location
  name                  = "my-key"
  type                  = "RSA"

  # Optional
  size = 2048
  opts = ["sign", "verify"]
  rotation_policy = {
    automatic = {
      time_before_expiry = "P30D"
    }
    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
  role_assignments = {
    crypto_user = {
      role_definition_id_or_name = "Key Vault Crypto User"
      principal_id               = data.azurerm_client_config.this.object_id
    }
  }
}
```

## Creating the key through Azure Resource Manager

Set `control_plane_enabled = true` to create the key through Azure Resource Manager
(`Microsoft.KeyVault/vaults/keys`, managed with AzAPI) instead of the Key Vault data plane. The
identity running Terraform then needs `Microsoft.KeyVault/vaults/keys/write` (for example Key Vault
Contributor) instead of a data plane role, and does not need network access to the vault. The
default is `false`, which keeps the data plane behaviour.

- Azure Resource Manager only creates the first version of a key. A request for a key that already
  exists returns it without writing anything, so a later change to `opts`, `size`, `curve`, the
  dates, `rotation_policy` or `tags` is shown in every plan but not applied. Change the key through
  the data plane, or create a key with a new name.
- `release_policy` is not supported.
- The `e`, `n`, `x`, `y`, `public_key_pem` and `public_key_openssh` outputs are `null`, because Azure
  Resource Manager does not return the public key.
- Switching an existing key between the two paths deletes it and creates new key material. Remove
  `azurerm_key_vault_key.this[0]` from the state and import `azapi_resource.this[0]` with the key's
  ARM resource ID instead, as the root module's README describes.
