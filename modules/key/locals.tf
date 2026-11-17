locals {
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

locals {
  # Azure Resource Manager takes the key's dates as seconds since 1970-01-01T00:00:00Z. The inputs
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
  # The request body of the key. Unset properties are left out: an action sends its body as it is,
  # so a null would reach Azure as an explicit null.
  control_plane_body = merge(
    {
      properties = merge(
        {
          attributes = merge({ enabled = true }, local.attribute_unix_times)
          keyOps     = var.opts
          kty        = var.type
        },
        var.curve == null ? {} : { curveName = var.curve },
        var.size == null ? {} : { keySize = var.size },
        var.rotation_policy == null ? {} : { rotationPolicy = local.control_plane_rotation_policy },
      )
    },
    var.tags == null ? {} : { tags = var.tags },
  )
  # The outputs come from a read of the key, so that they follow a rotation of the key. They fall
  # back to the response of the create request when the key can no longer be read.
  control_plane_output = var.control_plane_enabled ? {
    key_uri              = try(data.azapi_resource.this[0].output.properties.keyUri, azapi_resource_action.this[0].output.properties.keyUri)
    key_uri_with_version = try(data.azapi_resource.this[0].output.properties.keyUriWithVersion, azapi_resource_action.this[0].output.properties.keyUriWithVersion)
  } : null
  # The automatic rotation becomes a `rotate` action and `notify_before_expiry` a `notify` action,
  # as with the AzureRM provider.
  control_plane_rotation_policy = var.rotation_policy == null ? null : merge(
    var.rotation_policy.expire_after == null ? {} : { attributes = { expiryTime = var.rotation_policy.expire_after } },
    {
      lifetimeActions = concat(
        var.rotation_policy.automatic == null ? [] : [{
          action = { type = "rotate" }
          trigger = {
            for name, value in {
              timeAfterCreate  = var.rotation_policy.automatic.time_after_creation
              timeBeforeExpiry = var.rotation_policy.automatic.time_before_expiry
            } : name => value if value != null
          }
        }],
        var.rotation_policy.notify_before_expiry == null ? [] : [{
          action  = { type = "notify" }
          trigger = { timeBeforeExpiry = var.rotation_policy.notify_before_expiry }
        }],
      )
    },
  )
  resource_versionless_id = var.control_plane_enabled ? azapi_resource_action.this[0].resource_id : azurerm_key_vault_key.this[0].resource_versionless_id
}
