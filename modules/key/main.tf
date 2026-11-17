resource "azurerm_key_vault_key" "this" {
  count = var.control_plane_enabled ? 0 : 1

  key_opts        = var.opts
  key_type        = var.type
  key_vault_id    = var.key_vault_resource_id
  name            = var.name
  curve           = var.curve
  expiration_date = var.expiration_date
  key_size        = var.size
  not_before_date = var.not_before_date
  tags            = var.tags

  dynamic "release_policy" {
    for_each = var.release_policy != null ? [var.release_policy] : []

    content {
      json      = release_policy.value.json
      immutable = release_policy.value.immutable
    }
  }

  dynamic "rotation_policy" {
    for_each = var.rotation_policy != null ? [var.rotation_policy] : []

    content {
      expire_after         = rotation_policy.value.expire_after
      notify_before_expiry = rotation_policy.value.notify_before_expiry

      automatic {
        time_after_creation = rotation_policy.value.automatic.time_after_creation
        time_before_expiry  = rotation_policy.value.automatic.time_before_expiry
      }
    }
  }
}

# The data plane key became conditional when the control plane path was added. Existing keys keep
# their state at the first instance, so their key material is not replaced.
moved {
  from = azurerm_key_vault_key.this
  to   = azurerm_key_vault_key.this[0]
}

# The control plane path creates the key through Azure Resource Manager. The deploying identity needs
# `Microsoft.KeyVault/vaults/keys/write` (for example Key Vault Contributor) instead of a data plane
# role. Azure Resource Manager only creates the first version of a key: a request for a key that
# already exists returns it without writing anything, so later changes to the configuration are not
# applied to Azure.
#
# Azure Resource Manager has no DELETE for `Microsoft.KeyVault/vaults/keys` (405
# `DeleteNotSupported`), so an `azapi_resource` for a key could never be destroyed or removed from a
# configuration. The key is created with a PUT action instead. Destroying the action only forgets
# the key: it stays in the vault until it is deleted through the data plane or the vault is deleted.
resource "azapi_resource_action" "this" {
  count = var.control_plane_enabled ? 1 : 0

  method                 = "PUT"
  resource_id            = "${var.key_vault_resource_id}/keys/${var.name}"
  type                   = var.resource_types.keyvault_vaults_keys
  body                   = local.control_plane_body
  response_export_values = ["properties.keyUri", "properties.keyUriWithVersion"]
  retry                  = var.retry
  when                   = "apply"

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }
}

# An action is not refreshed, so the key's URIs are read here on every plan and follow a rotation of
# the key. A key that was deleted outside Terraform is not an error: the outputs then keep the URIs
# of the create request.
data "azapi_resource" "this" {
  count = var.control_plane_enabled ? 1 : 0

  resource_id            = azapi_resource_action.this[0].resource_id
  type                   = var.resource_types.keyvault_vaults_keys
  ignore_not_found       = true
  response_export_values = ["properties.keyUri", "properties.keyUriWithVersion"]
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      read = timeouts.value.read
    }
  }

  depends_on = [azapi_resource_action.this]
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = local.resource_versionless_id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}
