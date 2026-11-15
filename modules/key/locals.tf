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
  control_plane_body = {
    properties = {
      attributes = {
        enabled = true
        exp     = lookup(local.attribute_unix_times, "exp", null)
        nbf     = lookup(local.attribute_unix_times, "nbf", null)
      }
      curveName = var.curve
      keyOps    = var.opts
      keySize   = var.size
      kty       = var.type
      # The automatic rotation becomes a `rotate` action and `notify_before_expiry` a `notify` action,
      # as with the AzureRM provider. The values are the lower-case ones of the ARM schema; Azure
      # returns them capitalised, which `ignore_casing` on the resource absorbs.
      rotationPolicy = var.rotation_policy == null ? null : {
        attributes = var.rotation_policy.expire_after == null ? null : {
          expiryTime = var.rotation_policy.expire_after
        }
        lifetimeActions = concat(
          var.rotation_policy.automatic == null ? [] : [{
            action = { type = "rotate" }
            trigger = {
              timeAfterCreate  = var.rotation_policy.automatic.time_after_creation
              timeBeforeExpiry = var.rotation_policy.automatic.time_before_expiry
            }
          }],
          var.rotation_policy.notify_before_expiry == null ? [] : [{
            action = { type = "notify" }
            trigger = {
              timeAfterCreate  = null
              timeBeforeExpiry = var.rotation_policy.notify_before_expiry
            }
          }],
        )
      }
    }
  }
  resource_versionless_id = var.control_plane_enabled ? azapi_resource.this[0].id : azurerm_key_vault_key.this[0].resource_versionless_id
}
