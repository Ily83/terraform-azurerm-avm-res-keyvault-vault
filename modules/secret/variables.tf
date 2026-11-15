variable "key_vault_resource_id" {
  type        = string
  description = "The ID of the Key Vault where the secret should be created."
  nullable    = false

  validation {
    error_message = "Value must be a valid Azure Key Vault resource ID."
    condition     = can(regex("\\/subscriptions\\/[a-f\\d]{4}(?:[a-f\\d]{4}-){4}[a-f\\d]{12}\\/resourceGroups\\/[^\\/]+\\/providers\\/Microsoft.KeyVault\\/vaults\\/[^\\/]+$", var.key_vault_resource_id))
  }
}

variable "name" {
  type        = string
  description = "The name of the secret."
  nullable    = false

  validation {
    error_message = "Secret names may only contain alphanumerics and hyphens, and be between 1 and 127 characters in length."
    condition     = can(regex("^[A-Za-z0-9-]{1,127}$", var.name))
  }
}

variable "content_type" {
  type        = string
  default     = null
  description = "The content type of the secret."
}

variable "control_plane_enabled" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Whether to create the secret through Azure Resource Manager (`Microsoft.KeyVault/vaults/secrets`, managed with AzAPI) instead of the Key Vault data plane (`azurerm_key_vault_secret`). Defaults to `false`, which keeps the data plane behaviour of earlier versions.

With `true`:

- The identity running Terraform needs `Microsoft.KeyVault/vaults/secrets/write` on the vault (for example Key Vault Contributor or Contributor) and no Key Vault data plane role. Requests go to Azure Resource Manager, so the vault firewall and private endpoints do not apply to them.
- The value is sent through the write-only `sensitive_body`, so it is kept out of the state, and also out of the plan when it comes from the ephemeral `value_wo`. Azure Resource Manager never returns the value, so a refresh reads only the secret's metadata and Terraform cannot detect a value changed outside Terraform.
- The value is sent when the secret is created, when `value_wo_version` changes, and when another property of the secret (content type, dates or tags) changes. A change of `value` or `value_wo` alone is not sent until `value_wo_version` changes; this applies to `value` as well as to `value_wo`.
- Switching an existing secret between the two paths deletes it and creates it again, which fails while the deleted secret is soft-deleted. Move it in the state instead, as the root module's README describes.
DESCRIPTION
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = false
}

variable "expiration_date" {
  type        = string
  default     = null
  description = "The expiration date of the secret as a UTC datetime (Y-m-d'T'H:M:S'Z')."

  validation {
    error_message = "Value must be a UTC datetime (Y-m-d'T'H:M:S'Z')."
    condition     = var.expiration_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", var.expiration_date))
  }
}

variable "ignore_body_changes" {
  type = object({
    keyvault_vaults_secrets = optional(list(string), [])
  })
  default     = {}
  description = <<DESCRIPTION
Paths in each AzAPI resource's `body` whose changes the AzAPI provider ignores. Paths use dot notation, for example `properties.contentType`. Configuration changes at an ignored path are **not** sent to Azure until the path is removed from the list. Changes take effect only after an apply, because the value is held in provider-private state.

- `keyvault_vaults_secrets` - Ignored body paths for the secret when `control_plane_enabled` is `true`.
DESCRIPTION
  nullable    = false
}

variable "location" {
  type        = string
  default     = null
  description = "The Azure region for this module's resources or telemetry deployment."

  validation {
    condition     = !var.enable_telemetry || var.location != null
    error_message = "The location must not be null when telemetry is enabled."
  }
}

variable "not_before_date" {
  type        = string
  default     = null
  description = "Secret not usable before as a UTC datetime (Y-m-d'T'H:M:S'Z')."

  validation {
    error_message = "Value must be a UTC datetime (Y-m-d'T'H:M:S'Z')."
    condition     = var.not_before_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", var.not_before_date))
  }
}

variable "resource_types" {
  type = object({
    keyvault_vaults_secrets = optional(string, "Microsoft.KeyVault/vaults/secrets@2026-02-01")
  })
  default     = {}
  description = <<DESCRIPTION
AzAPI resource types and API versions used by the module, in `<provider>/<resource>@<api-version>` form. Each key defaults to a tested value; supply only the keys you want to override.

- `keyvault_vaults_secrets` - The secret, when `control_plane_enabled` is `true`.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string))
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
  })
  default     = null
  description = <<DESCRIPTION
Retry configuration applied to every `azapi` resource managed by the module. Defaults to `null` (no custom retry).

- `error_message_regex`  - (Optional) A list of regex patterns matching error messages that trigger a retry.
- `interval_seconds`     - (Optional) Initial interval between retries in seconds.
- `max_interval_seconds` - (Optional) Maximum interval between retries in seconds.

See <https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource#retry> for full semantics.
DESCRIPTION
}

variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<DESCRIPTION
A map of role assignments to create on the secret. The map key is deliberately arbitrary to avoid issues where map keys maybe unknown at plan time.

- `role_definition_id_or_name` - The ID or name of the role definition to assign to the principal.
- `principal_id` - The ID of the principal to assign the role to.
- `description` - The description of the role assignment.
- `skip_service_principal_aad_check` - If set to true, skips the Azure Active Directory check for the service principal in the tenant. Defaults to false.
- `condition` - The condition which will be used to scope the role assignment.
- `condition_version` - The version of the condition syntax. If you are using a condition, valid values are '2.0'.

> Note: only set `skip_service_principal_aad_check` to true if you are assigning a role to a service principal.
DESCRIPTION
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "The tags to assign to the secret."
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = null
  description = <<DESCRIPTION
Per-operation timeouts applied to every `azapi` resource managed by the module. Defaults to `null` (provider defaults). Each value is a Go duration string (e.g. `30m`, `1h`).

- `create` - (Optional) Timeout for create operations.
- `read`   - (Optional) Timeout for read operations.
- `update` - (Optional) Timeout for update operations.
- `delete` - (Optional) Timeout for delete operations.
DESCRIPTION
}

variable "value" {
  type        = string
  default     = null
  description = "The value for the secret. Must be set if `value_wo` is not set. With `control_plane_enabled`, a change of the value is sent only when `value_wo_version` changes."
  sensitive   = true
}

variable "value_wo" {
  type        = string
  default     = null
  description = "The value for the secret writable only. Must be set if `value` is not set."
  sensitive   = true
  ephemeral   = true
}

variable "value_wo_version" {
  type        = number
  default     = null
  description = "The version of the secret writable only. Must be set if `value_wo` is set. Changing this updates the secret value. With `control_plane_enabled`, it also controls when `value` is sent, and `null` counts as `0`."
}
