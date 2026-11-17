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
(`Microsoft.KeyVault/vaults/keys`) instead of the Key Vault data plane. The identity running
Terraform then needs `Microsoft.KeyVault/vaults/keys/write` and `read` (for example Key Vault
Contributor) instead of a data plane role. The default is `false`, which keeps the data plane
behaviour.

Azure Resource Manager has no delete operation for keys, so the module creates the key with an AzAPI
PUT action (`azapi_resource_action`) rather than managing it as a resource:

- Removing the module, renaming the key, setting `control_plane_enabled` back to `false` or running
  `terraform destroy` only removes the key from the state. It stays in the vault until it is deleted
  through the data plane (for example `az keyvault key delete`) or the vault is deleted.
- Azure Resource Manager reaches the vault as a trusted Microsoft service to create and read a key.
  When the vault firewall denies by default, it must let trusted services through
  (`network_acls.bypass = "AzureServices"` in the root module). With `bypass = "None"`, the root
  module's default, the request fails with `400 ForbiddenByFirewall`.
- Azure Resource Manager only creates the first version of a key. A request for a key that already
  exists returns it without writing anything, so a later change to `opts`, `size`, `curve`, the
  dates, `rotation_policy` or `tags` is sent but changes nothing in Azure, and Terraform does not
  report the difference. Change the key through the data plane, or create a key with a new name.
- Terraform does not track the key after creating it. A change made outside Terraform is neither
  detected nor reverted. Only the key's URIs are read on every plan, so the outputs follow a rotation
  of the key.
- `release_policy` is not supported.
- The `e`, `n`, `x`, `y`, `public_key_pem` and `public_key_openssh` outputs are `null`, because Azure
  Resource Manager does not return the public key.
- Switching an existing data plane key to the control plane would first delete it through the data
  plane. Remove `azurerm_key_vault_key.this[0]` from the state before applying instead, as the root
  module's README describes.
