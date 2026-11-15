# terraform-azurerm-avm-res-keyvault-vault

Module to deploy key vaults, keys and secrets in Azure.

## Recovering a soft-deleted key vault

A deleted key vault stays in the soft-deleted state for its retention period and keeps its name, so
creating a vault with that name fails. With purge protection, the vault cannot be purged earlier. To
bring the vault back with its keys, secrets and certificates:

1. Set `create_mode = "recover"` and apply. Azure restores the vault as it was and ignores the other
   properties of that request.
1. Set `create_mode` back to `null` and apply again. This brings the vault in line with the
   configuration and recreates its role assignments, which a recovery does not restore.

The `recover_soft_deleted_key_vaults` feature of the AzureRM provider has no effect on this module,
which manages the key vault with AzAPI.

## Creating secrets and keys through Azure Resource Manager

By default the module writes secrets and keys through the Key Vault data plane, with the AzureRM
provider. The identity running Terraform then needs a Key Vault data plane role (for example Key
Vault Secrets Officer or Key Vault Crypto Officer), network access to the vault endpoint, and every
refresh reads the secret back.

Set `control_plane_enabled = true` on an entry of `secrets` or `keys` to create it through Azure
Resource Manager instead (`Microsoft.KeyVault/vaults/secrets` and `Microsoft.KeyVault/vaults/keys`,
managed with AzAPI). The identity then needs `Microsoft.KeyVault/vaults/secrets/write` or
`Microsoft.KeyVault/vaults/keys/write`, which Key Vault Contributor and Contributor include, and no
data plane role. The requests go to Azure Resource Manager, so the vault firewall and private
endpoints do not apply to them. The setting is per entry and defaults to `false`, so existing
configurations plan no change.

```hcl
secrets = {
  session = {
    name                  = "session-key"
    control_plane_enabled = true
  }
}
secrets_value_wo         = { session = ephemeral.random_password.session.result }
secrets_value_wo_version = { session = 1 }
```

Trade-offs of the control plane path:

- **Secret values are write-only.** The value is sent in the AzAPI `sensitive_body`, a write-only
  argument, so it is kept out of the state, and also out of the plan when it comes from
  `secrets_value_wo` (a value in `secrets_value` is still saved as an input variable in a plan file).
  Azure Resource Manager never returns it. A refresh reads only the secret's metadata, so Terraform
  cannot detect a value that was changed outside Terraform.
- **A new value needs a version bump.** The value is sent when the secret is created, when its
  `secrets_value_wo_version` entry changes, and with any change to the secret's content type, dates
  or tags. Changing only the value in `secrets_value` or `secrets_value_wo` is not sent until the
  version changes. A missing version counts as `0`.
- **Keys are created once.** Azure Resource Manager only creates the first version of a key; a
  request for a key that already exists returns it without writing anything. A later change to the
  key's options, size, curve, dates, rotation policy or tags is shown in every plan but is not
  applied. Change the key through the data plane, or create a key with a new name. Azure rotates the
  key according to its rotation policy as usual.
- **Key limits.** `release_policy` is not supported, and the `e`, `n`, `x`, `y`, `public_key_pem`
  and `public_key_openssh` attributes of the `keys` output are `null`, because Azure Resource
  Manager does not return the public key.
- **Role assignments on the secret or key** are still created with the AzureRM provider, scoped to
  the secret's or key's ARM resource ID.

`resource_types.keyvault_vaults_secrets`, `resource_types.keyvault_vaults_keys` and the matching
`ignore_body_changes` slots are passed to the submodules, together with `retry` and `timeouts`.

### Switching an existing secret or key

Changing `control_plane_enabled` on an existing entry would delete the secret or key and create it
again: the new create then fails while the deleted object is soft-deleted, and a deleted key's key
material is lost. Move the object in the state instead, before applying. Apply this module version
once without switching first, so that the `moved` blocks have put the existing secrets and keys at the
`[0]` addresses used below. For a secret moving to the control plane:

```pwsh
terraform state rm 'module.<module-name>.module.secrets["<key>"].azurerm_key_vault_secret.this[0]'
```

```hcl
import {
  to = module.<module-name>.module.secrets["<key>"].azapi_resource.this[0]
  id = "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.KeyVault/vaults/<vault-name>/secrets/<secret-name>?api-version=2026-02-01"
}
```

The first apply after the import writes the value again, as a new version of the secret. For a key,
use `module.keys["<key>"].azurerm_key_vault_key.this[0]`, `module.keys["<key>"].azapi_resource.this[0]`
and `/keys/<key-name>` in the ID; the key itself is not changed. To move back to the data plane, remove
the `azapi_resource.this[0]` address from the state and import `azurerm_key_vault_secret.this[0]` or
`azurerm_key_vault_key.this[0]` with the versioned data plane URI of the secret or key as the ID.

## Upgrading from a version that used the AzureRM provider for the key vault

Versions up to 0.12.x managed the key vault itself with the AzureRM provider. This version manages
the key vault, its access policies, lock, role assignments, diagnostic settings and private endpoints
with AzAPI, and includes `moved` blocks so the key vault, its lock, role assignments, diagnostic
settings, private endpoints and their locks move to their AzAPI addresses without being recreated.

Keys, secrets and certificate contacts still use the AzureRM provider by default and are migrated in
a later release. Secrets and keys can be created through Azure Resource Manager instead, as described
above.

When calling the key or secret submodule directly, supply `location` for telemetry, which is enabled
by default. Existing direct submodule callers that do not supply a location must either add one or
set `enable_telemetry = false`. The root module passes its location and telemetry setting to both
submodules.

1. Replace `resource_group_name` with `parent_id`, the resource ID of the resource group:

   ```hcl
   parent_id = "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>"
   ```

1. If the module manages private DNS zone groups, add the `import` block described below.
1. Run `terraform init -upgrade`, then `terraform plan`.
1. Expect in-place updates while AzAPI takes over the existing resources. The plan can also add local
   `time_sleep` and `terraform_data` resources. When telemetry is enabled, the vault, interfaces
   module and each key and secret submodule create empty subscription-scope Azure deployments for
   telemetry. Nothing being migrated should be destroyed or replaced; do not apply a plan that
   destroys or replaces any of those resources.
1. Apply the plan and inspect a second plan for unexpected changes to the migrated resources.
   Telemetry deployments can show an update because they include the current plan timestamp.

Access policies and application security groups need no action. Azure models both as part of their
parent rather than as addressable child resources, so from this version they are sent in the body of
the key vault and the private endpoint respectively. The old `azurerm_key_vault_access_policy` and
`azurerm_private_endpoint_application_security_group_association` resources are dropped from the
state without being deleted: the plan reports them as "will no longer be managed by Terraform, but
will not be destroyed", and Azure keeps the policies and associations themselves.

When `legacy_access_policies_enabled` is false the module does not manage access policies at all. It
re-reads whatever is on the vault and sends it back unchanged, so policies set by another
configuration are left in place.

Three cases need extra steps:

- **Private DNS zone groups managed by the module** (`private_endpoints_manage_dns_zone_group` is
  true, the default, and a private endpoint sets `private_dns_zone_resource_ids`). The AzureRM
  provider kept the zone group inside the private endpoint, so there is no separate address for a
  `moved` block to start from, and AzAPI does not take over an existing resource it did not create.
  Import each zone group once with an `import` block in your root module:

  ```hcl
  import {
    to = module.<module-name>.azapi_resource.private_dns_zone_groups["<key>"]
    id = "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Network/privateEndpoints/<private-endpoint-name>/privateDnsZoneGroups/<zone-group-name>?api-version=2025-05-01"
  }
  ```

  `<key>` is the key of the `private_endpoints` entry, `<private-endpoint-name>` is its `name`
  (`pe-<key vault name>` by default), and `<zone-group-name>` is its `private_dns_zone_group_name`
  (`default` by default). The import leaves the zone group and its DNS records unchanged. Without it,
  the apply stops with `Resource already exists` after upgrading everything else, and nothing in Azure
  is removed; add the block and apply again. Remove the block once the upgrade is applied.

- **`ReadOnly` lock.** The upgrade updates the key vault and its private endpoints in place, which a
  `ReadOnly` lock on either blocks. Before upgrading, apply your configuration without those locks
  using the old version, then upgrade and restore the locks.

- **Cross-tenant role assignments** (those that set `delegated_managed_identity_resource_id`, for
  example with Azure Lighthouse). The AzureRM provider stored their ID with a `|<tenant-id>` suffix
  that the `moved` block cannot convert. Before planning, remove each one from the state, then import
  it at its new address with an `import` block in your root module:

  ```pwsh
  terraform state rm 'module.<module-name>.azurerm_role_assignment.this["<key>"]'
  ```

  ```hcl
  import {
    to = module.<module-name>.azapi_resource.role_assignments["<key>"]
    id = "<role assignment resource ID, without the |<tenant-id> suffix>"
  }
  ```

The `uri` output is now read from the key vault's `properties.vaultUri` rather than the AzureRM
`vault_uri` attribute, and returns the same value.

The `private_endpoints` output no longer returns the entire AzureRM resource. It returns the
attributes listed in its description, under the names and shapes the AzureRM provider used, so
references such as `id`, `name` and `private_service_connection[0].private_ip_address` return the same
values as before.
