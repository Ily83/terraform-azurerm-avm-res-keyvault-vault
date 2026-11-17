locals {
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

locals {
  # Azure Resource Manager takes the secret's dates as seconds since 1970-01-01T00:00:00Z. The inputs
  # are UTC datetimes (validated as Y-m-d'T'H:M:S'Z'), converted here with the days-from-civil
  # algorithm because Terraform has no built-in function for it.
  attribute_date_parts = {
    for name, date in { exp = var.expiration_date, nbf = var.not_before_date } :
    name => [for part in regex("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})Z$", date) : tonumber(part)]
    if date != null
  }
  # The year starts in March so that the leap day is the last day of the year.
  attribute_dates_shifted = {
    for name, part in local.attribute_date_parts : name => {
      day     = part[2]
      month   = part[1] > 2 ? part[1] - 3 : part[1] + 9
      seconds = part[3] * 3600 + part[4] * 60 + part[5]
      year    = part[1] <= 2 ? part[0] - 1 : part[0]
    }
  }
  attribute_dates_civil = {
    for name, date in local.attribute_dates_shifted : name => merge(date, {
      day_of_year  = floor((153 * date.month + 2) / 5) + date.day - 1
      era          = floor(date.year / 400)
      year_of_era  = date.year - floor(date.year / 400) * 400
      unix_day_gap = 719468 # Days from 0000-03-01 to 1970-01-01.
    })
  }
  attribute_unix_times = {
    for name, civil in local.attribute_dates_civil : name => (civil.era * 146097 + civil.year_of_era * 365 + floor(civil.year_of_era / 4) - floor(civil.year_of_era / 100) + civil.day_of_year - civil.unix_day_gap) * 86400 + civil.seconds
  }
  # The request body of the secret. Unset properties are left out: an action sends its body as it
  # is, so a null would reach Azure as an explicit null.
  control_plane_body = merge(
    {
      properties = merge(
        { attributes = merge({ enabled = true }, local.attribute_unix_times) },
        var.content_type == null ? {} : { contentType = var.content_type },
      )
    },
    var.tags == null ? {} : { tags = var.tags },
  )
  # The outputs come from a read of the secret, so that they follow a version created outside
  # Terraform. They fall back to the response of the last write when the secret can no longer be read.
  control_plane_output = var.control_plane_enabled ? {
    secret_uri              = try(data.azapi_resource.this[0].output.properties.secretUri, azapi_resource_action.this[0].output.properties.secretUri)
    secret_uri_with_version = try(data.azapi_resource.this[0].output.properties.secretUriWithVersion, azapi_resource_action.this[0].output.properties.secretUriWithVersion)
  } : null
  # AzAPI sends the value only when this version changes, and Terraform only writes the secret again
  # when the body, the resource type or this version changes. The version therefore includes a hash
  # of the body and the type, so every request that writes the secret carries its value rather than
  # relying on how Azure Resource Manager treats a secret PUT without one. Any other argument of the
  # action that is made variable later has to be added to the hash for the same reason. A change of
  # the value alone is sent only when `value_wo_version` changes, because the value itself is never
  # compared.
  control_plane_value_version = "${coalesce(var.value_wo_version, 0)}-${substr(sha256(jsonencode({ body = local.control_plane_body, type = var.resource_types.keyvault_vaults_secrets })), 0, 16)}"
  resource_versionless_id     = var.control_plane_enabled ? azapi_resource_action.this[0].resource_id : azurerm_key_vault_secret.this[0].resource_versionless_id
}
