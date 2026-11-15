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
  parent_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test"
  name             = "test"
  location         = "eastus"
  tenant_id        = "00000000-0000-0000-0000-000000000000"
}

run "create_mode_is_not_sent_by_default" {
  command = plan

  assert {
    condition     = azapi_resource.this.body.properties.createMode == null
    error_message = "The create mode must not be sent unless it is set."
  }
  assert {
    condition     = azapi_resource.this.ignore_null_property
    error_message = "Null properties must be left out of the request, so an unset create mode is not sent."
  }
}

run "create_mode_recover_is_sent" {
  command = plan

  variables {
    create_mode = "recover"
  }

  assert {
    condition     = azapi_resource.this.body.properties.createMode == "recover"
    error_message = "The create mode `recover` must be sent in the body of the key vault."
  }
}

run "create_mode_default_is_sent" {
  command = plan

  variables {
    create_mode = "default"
  }

  assert {
    condition     = azapi_resource.this.body.properties.createMode == "default"
    error_message = "The create mode `default` must be sent in the body of the key vault."
  }
}

run "create_mode_rejects_unknown_value" {
  command = plan

  variables {
    create_mode = "Recover"
  }

  expect_failures = [
    var.create_mode,
  ]
}
