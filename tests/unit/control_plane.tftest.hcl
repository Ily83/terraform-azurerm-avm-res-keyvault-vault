mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}
mock_provider "azurerm" {}
mock_provider "random" {}
mock_provider "time" {}

variables {
  enable_telemetry = false
  location         = "eastus"
}

# Secret submodule

run "secret_default_uses_data_plane" {
  command = plan

  module {
    source = "./modules/secret"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "plain"
    value                 = "secret-value"
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 1 && length(azapi_resource.this) == 0
    error_message = "Without control_plane_enabled the secret must stay on the data plane resource only."
  }
}

run "secret_control_plane_body" {
  command = plan

  module {
    source = "./modules/secret"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    control_plane_enabled = true
    content_type          = "text/plain"
    expiration_date       = "2026-01-01T00:00:00Z"
    not_before_date       = "2000-02-29T12:34:56Z"
    tags                  = { env = "test" }
    value_wo              = "secret-value-wo"
    value_wo_version      = 3
  }

  assert {
    condition     = length(azurerm_key_vault_secret.this) == 0 && length(azapi_resource.this) == 1
    error_message = "With control_plane_enabled the secret must be an AzAPI resource only."
  }
  assert {
    condition     = azapi_resource.this[0].type == "Microsoft.KeyVault/vaults/secrets@2026-02-01"
    error_message = "The secret must use the default resource type."
  }
  assert {
    condition     = azapi_resource.this[0].parent_id == var.key_vault_resource_id && azapi_resource.this[0].name == "cp"
    error_message = "The secret must be created under the key vault with its name."
  }
  assert {
    condition     = azapi_resource.this[0].body.properties.contentType == "text/plain"
    error_message = "content_type must map to properties.contentType."
  }
  assert {
    condition     = azapi_resource.this[0].body.properties.attributes.exp == 1767225600 && azapi_resource.this[0].body.properties.attributes.nbf == 951827696
    error_message = "The dates must be sent as seconds since 1970-01-01T00:00:00Z."
  }
  assert {
    condition     = azapi_resource.this[0].body.properties.attributes.enabled == true
    error_message = "The secret must be created enabled."
  }
  assert {
    condition     = !can(azapi_resource.this[0].body.properties.value)
    error_message = "The value must never be part of body; it belongs in sensitive_body."
  }
  assert {
    condition     = startswith(azapi_resource.this[0].sensitive_body_version["properties.value"], "3-")
    error_message = "sensitive_body_version must start with value_wo_version."
  }
  assert {
    condition     = azapi_resource.this[0].tags["env"] == "test"
    error_message = "Tags must be set on the secret."
  }
  assert {
    condition     = azapi_resource.this[0].ignore_null_property == true
    error_message = "Unset properties must not be sent."
  }
}

run "secret_control_plane_plain_value_without_version" {
  command = plan

  module {
    source = "./modules/secret"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    control_plane_enabled = true
    value                 = "secret-value"
  }

  assert {
    condition     = startswith(azapi_resource.this[0].sensitive_body_version["properties.value"], "0-")
    error_message = "A missing value_wo_version must count as 0."
  }
  assert {
    condition     = lookup(azapi_resource.this[0].body.properties.attributes, "exp", null) == null && lookup(azapi_resource.this[0].body.properties, "contentType", null) == null
    error_message = "Unset dates and content type must be null so that they are not sent."
  }
}

run "secret_control_plane_resource_type_override" {
  command = plan

  module {
    source = "./modules/secret"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    control_plane_enabled = true
    value                 = "secret-value"
    resource_types = {
      keyvault_vaults_secrets = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
    }
    ignore_body_changes = {
      keyvault_vaults_secrets = ["properties.contentType"]
    }
    retry = {
      error_message_regex = ["Conflict"]
    }
    timeouts = {
      create = "10m"
    }
  }

  assert {
    condition     = azapi_resource.this[0].type == "Microsoft.KeyVault/vaults/secrets@2023-07-01"
    error_message = "resource_types must override the secret type."
  }
  assert {
    condition     = azapi_resource.this[0].retry.error_message_regex[0] == "Conflict"
    error_message = "retry must reach the secret."
  }
  assert {
    condition     = azapi_resource.this[0].timeouts.create == "10m"
    error_message = "timeouts must reach the secret."
  }
}

run "secret_control_plane_requires_value" {
  command = plan

  module {
    source = "./modules/secret"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    control_plane_enabled = true
  }

  expect_failures = [azapi_resource.this]
}

run "secret_control_plane_outputs" {
  command = apply

  module {
    source = "./modules/secret"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    control_plane_enabled = true
    value_wo              = "secret-value-wo"
    value_wo_version      = 1
  }

  override_resource {
    target = azapi_resource.this[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/secrets/cp"
      output = {
        properties = {
          secretUri            = "https://test.vault.azure.net/secrets/cp"
          secretUriWithVersion = "https://test.vault.azure.net/secrets/cp/0123456789abcdef"
        }
      }
    }
  }

  assert {
    condition     = output.id == "https://test.vault.azure.net/secrets/cp/0123456789abcdef"
    error_message = "id must be the versioned secret URI."
  }
  assert {
    condition     = output.versionless_id == "https://test.vault.azure.net/secrets/cp"
    error_message = "versionless_id must be the versionless secret URI."
  }
  assert {
    condition     = output.resource_versionless_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/secrets/cp"
    error_message = "resource_versionless_id must be the ARM resource ID."
  }
  assert {
    condition     = output.resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/secrets/cp/versions/0123456789abcdef"
    error_message = "resource_id must be the versioned ARM resource ID."
  }
  assert {
    condition     = output.name == "cp"
    error_message = "name must be the secret name."
  }
}

# Key submodule

run "key_default_uses_data_plane" {
  command = plan

  module {
    source = "./modules/key"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "ordinary"
    type                  = "RSA"
    size                  = 2048
  }

  assert {
    condition     = length(azurerm_key_vault_key.this) == 1 && length(azapi_resource.this) == 0
    error_message = "Without control_plane_enabled the key must stay on the data plane resource only."
  }
}

run "key_control_plane_body" {
  command = plan

  module {
    source = "./modules/key"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    type                  = "RSA"
    size                  = 2048
    opts                  = ["sign", "verify"]
    control_plane_enabled = true
    expiration_date       = "2026-01-01T00:00:00Z"
    tags                  = { env = "test" }
    rotation_policy = {
      automatic = {
        time_after_creation = "P180D"
      }
      expire_after         = "P365D"
      notify_before_expiry = "P30D"
    }
  }

  assert {
    condition     = length(azurerm_key_vault_key.this) == 0 && length(azapi_resource.this) == 1
    error_message = "With control_plane_enabled the key must be an AzAPI resource only."
  }
  assert {
    condition     = azapi_resource.this[0].type == "Microsoft.KeyVault/vaults/keys@2026-02-01"
    error_message = "The key must use the default resource type."
  }
  assert {
    condition     = azapi_resource.this[0].body.properties.kty == "RSA" && azapi_resource.this[0].body.properties.keySize == 2048
    error_message = "type and size must map to kty and keySize."
  }
  assert {
    condition     = jsonencode(azapi_resource.this[0].body.properties.keyOps) == jsonencode(["sign", "verify"])
    error_message = "opts must map to keyOps."
  }
  assert {
    condition     = azapi_resource.this[0].body.properties.attributes.exp == 1767225600
    error_message = "expiration_date must be sent as seconds since 1970-01-01T00:00:00Z."
  }
  assert {
    condition     = azapi_resource.this[0].body.properties.rotationPolicy.attributes.expiryTime == "P365D"
    error_message = "expire_after must map to rotationPolicy.attributes.expiryTime."
  }
  assert {
    condition = (
      length(azapi_resource.this[0].body.properties.rotationPolicy.lifetimeActions) == 2 &&
      azapi_resource.this[0].body.properties.rotationPolicy.lifetimeActions[0].action.type == "rotate" &&
      azapi_resource.this[0].body.properties.rotationPolicy.lifetimeActions[0].trigger.timeAfterCreate == "P180D" &&
      azapi_resource.this[0].body.properties.rotationPolicy.lifetimeActions[1].action.type == "notify" &&
      azapi_resource.this[0].body.properties.rotationPolicy.lifetimeActions[1].trigger.timeBeforeExpiry == "P30D"
    )
    error_message = "The rotation policy must become a rotate and a notify lifetime action."
  }
  assert {
    condition     = azapi_resource.this[0].ignore_casing == true
    error_message = "Azure returns the action types capitalised, so casing must be ignored."
  }
  assert {
    condition     = azapi_resource.this[0].tags["env"] == "test"
    error_message = "Tags must be set on the key."
  }
}

run "key_control_plane_without_rotation_policy" {
  command = plan

  module {
    source = "./modules/key"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    type                  = "EC"
    curve                 = "P-384"
    control_plane_enabled = true
  }

  assert {
    condition     = azapi_resource.this[0].body.properties.curveName == "P-384" && azapi_resource.this[0].body.properties.rotationPolicy == null
    error_message = "curve must map to curveName, and no rotation policy must be sent when none is set."
  }
}

run "key_control_plane_rejects_release_policy" {
  command = plan

  module {
    source = "./modules/key"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    type                  = "RSA-HSM"
    size                  = 2048
    control_plane_enabled = true
    release_policy = {
      json = jsonencode({ version = "1.0.0" })
    }
  }

  expect_failures = [var.release_policy]
}

run "key_control_plane_outputs" {
  command = apply

  module {
    source = "./modules/key"
  }

  variables {
    key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
    name                  = "cp"
    type                  = "RSA"
    size                  = 2048
    control_plane_enabled = true
  }

  override_resource {
    target = azapi_resource.this[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/keys/cp"
      output = {
        properties = {
          keyUri            = "https://test.vault.azure.net/keys/cp"
          keyUriWithVersion = "https://test.vault.azure.net/keys/cp/0123456789abcdef"
        }
      }
    }
  }

  assert {
    condition     = output.id == "https://test.vault.azure.net/keys/cp/0123456789abcdef" && output.versionless_id == "https://test.vault.azure.net/keys/cp"
    error_message = "id and versionless_id must be the key URIs."
  }
  assert {
    condition     = output.resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/keys/cp/versions/0123456789abcdef"
    error_message = "resource_id must be the versioned ARM resource ID."
  }
  assert {
    condition     = output.resource_versionless_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/keys/cp"
    error_message = "resource_versionless_id must be the ARM resource ID."
  }
  assert {
    condition     = output.n == null && output.e == null && output.public_key_pem == null && output.release_policy_configured == false
    error_message = "Public key outputs must be null on the control plane path."
  }
}

# Root module

run "root_mixes_both_paths" {
  command = apply

  variables {
    parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test"
    name      = "test"
    tenant_id = "00000000-0000-0000-0000-000000000000"
    secrets = {
      plain = {
        name = "plain-secret"
      }
      cp = {
        name                  = "cp-secret"
        control_plane_enabled = true
      }
    }
    secrets_value = {
      plain = "secret-value"
      cp    = "cp-secret-value"
    }
    keys = {
      plain = {
        name     = "plain-key"
        key_type = "RSA"
        key_size = 2048
      }
      cp = {
        name                  = "cp-key"
        key_type              = "RSA"
        key_size              = 2048
        control_plane_enabled = true
      }
    }
    resource_types = {
      keyvault_vaults_secrets = {
        keyvault_vaults_secrets = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
      }
    }
  }

  override_resource {
    target = azapi_resource.this
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test"
      output = {
        properties = {
          vaultUri = "https://test.vault.azure.net/"
        }
      }
    }
  }
  override_resource {
    target = module.secrets["cp"].azapi_resource.this[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/secrets/cp-secret"
      output = {
        properties = {
          secretUri            = "https://test.vault.azure.net/secrets/cp-secret"
          secretUriWithVersion = "https://test.vault.azure.net/secrets/cp-secret/1"
        }
      }
    }
  }
  override_resource {
    target = module.keys["cp"].azapi_resource.this[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.KeyVault/vaults/test/keys/cp-key"
      output = {
        properties = {
          keyUri            = "https://test.vault.azure.net/keys/cp-key"
          keyUriWithVersion = "https://test.vault.azure.net/keys/cp-key/1"
        }
      }
    }
  }

  assert {
    condition     = output.secrets_resource_ids["cp"].id == "https://test.vault.azure.net/secrets/cp-secret/1"
    error_message = "The control plane secret must be reported from the AzAPI resource."
  }
  assert {
    condition     = output.keys_resource_ids["cp"].versionless_id == "https://test.vault.azure.net/keys/cp-key"
    error_message = "The control plane key must be reported from the AzAPI resource."
  }
  assert {
    condition     = output.secrets_resource_ids["plain"].name == "plain-secret" && output.keys_resource_ids["plain"].name == "plain-key"
    error_message = "Items without control_plane_enabled must still be created."
  }
}

run "root_rejects_control_plane_release_policy" {
  command = plan

  variables {
    parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test"
    name      = "test"
    tenant_id = "00000000-0000-0000-0000-000000000000"
    keys = {
      invalid = {
        name                  = "invalid"
        key_type              = "RSA-HSM"
        key_size              = 2048
        control_plane_enabled = true
        release_policy = {
          json = jsonencode({ version = "1.0.0" })
        }
      }
    }
  }

  expect_failures = [var.keys]
}
