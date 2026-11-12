# Plan-only tests of the identity module used on its own, against mocked providers: no Azure
# account, no credentials. Every name below is synthetic.

mock_provider "azurerm" {}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"
  tags                = { environment = "example" }
}

run "creates_one_named_identity" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.this.name == "id-pw-example"
    error_message = "The identity must be named from name."
  }

  assert {
    condition     = azurerm_user_assigned_identity.this.tags == tomap({ environment = "example" })
    error_message = "The identity must carry the tags it is given."
  }
}

run "refuses_a_name_with_capitals" {
  command = plan

  variables {
    name = "PW-Example"
  }

  expect_failures = [var.name]
}
