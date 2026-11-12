# Plan-only tests of the logs module used on its own, against mocked providers: no Azure account,
# no credentials. Every name below is synthetic.

mock_provider "azurerm" {}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"
}

run "keeps_logs_90_days_by_default" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-pw-example"
    error_message = "The workspace must be named from name."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90
    error_message = "The workspace must keep logs 90 days by default."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "The workspace must use the pay-as-you-go SKU."
  }
}

run "log_retention_comes_from_the_input" {
  command = plan

  variables {
    retention_days = 365
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 365
    error_message = "The workspace must keep logs for retention_days."
  }
}

run "refuses_log_retention_under_30_days" {
  command = plan

  variables {
    retention_days = 7
  }

  expect_failures = [var.retention_days]
}

run "refuses_log_retention_over_730_days" {
  command = plan

  variables {
    retention_days = 731
  }

  expect_failures = [var.retention_days]
}
