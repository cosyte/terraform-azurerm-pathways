# Plan-only tests of the root module's deployment shapes beyond its defaults: a PostgreSQL server
# you already run, HTTP as the only intake, and a warm standby replica. Mocked providers: no Azure
# account, no credentials. Every id and name below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example"
    }
  }
}

mock_provider "azapi" {}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
    }
  }

  mllp_ports = [2575]

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/example.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }
}

run "an_existing_postgres_server_makes_no_server" {
  command = plan

  variables {
    postgres = null
    existing_postgres = {
      database_url_secret_name = "existing-database-url"
    }
  }

  assert {
    condition     = output.postgres == null
    error_message = "With existing_postgres the postgres output must be null: the module made no server."
  }

  assert {
    condition     = output.database_url_secret_name == "existing-database-url"
    error_message = "The app must read the database URL from the existing secret."
  }
}

run "the_module_server_writes_its_own_secret" {
  command = plan

  assert {
    condition     = output.postgres.administrator_login == "pathways_admin"
    error_message = "With postgres the module must make the PostgreSQL server."
  }

  assert {
    condition     = output.database_url_secret_name == "database-url"
    error_message = "With postgres the app must read the database-url secret the module writes."
  }
}

run "http_only_and_a_standby_reach_the_app" {
  command = plan

  variables {
    mllp_ports      = []
    http_port       = 8080
    standby_replica = true
  }

  assert {
    condition     = output.http_port == 8080 && output.mllp_ports == tolist([])
    error_message = "http_port must reach the outputs, with no MLLP port."
  }

  assert {
    condition     = output.standby_replica == true
    error_message = "standby_replica must reach the outputs."
  }
}

run "refuses_both_postgres_and_existing_postgres" {
  command = plan

  variables {
    existing_postgres = {
      database_url_secret_name = "existing-database-url"
    }
  }

  expect_failures = [var.existing_postgres]
}

run "refuses_neither_postgres_nor_existing_postgres" {
  command = plan

  variables {
    postgres = null
  }

  expect_failures = [var.existing_postgres]
}

run "refuses_neither_mllp_nor_http" {
  command = plan

  variables {
    mllp_ports = []
  }

  expect_failures = [var.mllp_ports]
}
