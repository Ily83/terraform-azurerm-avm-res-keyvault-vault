resource "azurerm_key_vault_secret" "this" {
  count = var.control_plane_enabled ? 0 : 1

  key_vault_id     = var.key_vault_resource_id
  name             = var.name
  content_type     = var.content_type
  expiration_date  = var.expiration_date
  not_before_date  = var.not_before_date
  tags             = var.tags
  value            = var.value
  value_wo         = var.value_wo
  value_wo_version = var.value_wo_version
}

# The data plane secret became conditional when the control plane path was added. Existing secrets
# keep their state at the first instance and are not recreated.
moved {
  from = azurerm_key_vault_secret.this
  to   = azurerm_key_vault_secret.this[0]
}

# The control plane path writes the secret through Azure Resource Manager. The deploying identity
# needs `Microsoft.KeyVault/vaults/secrets/write` (for example Key Vault Contributor) instead of a
# data plane role, and the vault firewall does not apply. Azure never returns the value, so it is
# sent through `sensitive_body`, which is write-only and kept out of the plan and the state.
resource "azapi_resource" "this" {
  count = var.control_plane_enabled ? 1 : 0

  name                   = var.name
  parent_id              = var.key_vault_resource_id
  type                   = var.resource_types.keyvault_vaults_secrets
  body                   = local.control_plane_body
  ignore_body_changes    = length(var.ignore_body_changes.keyvault_vaults_secrets) > 0 ? var.ignore_body_changes.keyvault_vaults_secrets : null
  ignore_null_property   = true
  response_export_values = ["properties.secretUri", "properties.secretUriWithVersion"]
  retry                  = var.retry
  sensitive_body = {
    properties = {
      value = var.value_wo != null ? var.value_wo : var.value
    }
  }
  sensitive_body_version = {
    "properties.value" = local.control_plane_value_version
  }
  tags = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]

    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    precondition {
      condition     = var.value != null || var.value_wo != null
      error_message = "A secret created through the control plane needs a value: set `value` or `value_wo`."
    }
  }
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
