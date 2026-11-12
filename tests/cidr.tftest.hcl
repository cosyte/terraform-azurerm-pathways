# Plan-only tests of the MLLP address guard on the root module's ingress_allowed_cidrs, against
# mocked providers: no Azure account, no credentials. Every id and name below is synthetic. The same
# cases run against the container_apps module on its own, in modules/container_apps/tests.

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

# Ranges just inside the address guard's bounds, and the wide ranges it lets through only with the
# unsafe opt-in.
run "narrowest_bounds_pass_without_the_opt_in" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["10.0.0.0/8", "2001:db8::/32", "::ffff:198.51.100.0/120", "::ffff:10.0.0.0/104"]
  }

  assert {
    condition     = sort(keys(output.slots)) == tolist(["blue"])
    error_message = "Ranges at /8 (IPv4), /32 (IPv6) or narrower must plan without the opt-in."
  }
}

run "wide_ranges_pass_only_with_the_opt_in" {
  command = plan

  variables {
    internal_load_balancer_enabled     = false
    ingress_allowed_cidrs              = ["0.0.0.0/1", "128.0.0.0/1", "::ffff:0:0/96", "2001:db8::/31"]
    unsafe_allow_mllp_from_any_address = true
  }

  assert {
    condition     = sort(keys(output.slots)) == tolist(["blue"])
    error_message = "With the opt-in, wide ranges must plan."
  }
}

# The address guard refuses this list unless the unsafe opt-in is set. ::ffff:0:0/96 holds every
# IPv4 address in IPv4-mapped IPv6 form.
run "refuses_ipv4_mapped_all" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["::ffff:0:0/96"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. An IPv4-mapped IPv6 range as
# wide as an IPv4 /1.
run "refuses_ipv4_mapped_wide" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["::ffff:128.0.0.0/97"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. An IPv4 range shorter than
# /8.
run "refuses_ipv4_shorter_than_8" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["10.0.0.0/7"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. Two /1 ranges that together
# cover every IPv4 address.
run "refuses_ipv4_two_halves" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["0.0.0.0/1", "128.0.0.0/1"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. The IPv6 /0 written out in
# full.
run "refuses_ipv6_any_long_form" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["0:0:0:0:0:0:0:0/0"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. ::/80 is a /80, but it holds
# the whole IPv4-mapped range.
run "refuses_ipv6_holding_the_ipv4_mapped_range" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["::/80"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. ::/00 is the IPv6 /0 written
# with a leading zero.
run "refuses_ipv6_prefix_00" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["::/00"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. An IPv6 range shorter than
# /32.
run "refuses_ipv6_shorter_than_32" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["2001:db8::/31"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. An entry with a space before
# it is not a plain CIDR range.
run "refuses_leading_space" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = [" 198.51.100.0/24"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. 0.0.0.0/00 is a /0 written
# with a leading zero: refused as malformed and as wide.
run "refuses_prefix_00" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["198.51.100.0/24", "0.0.0.0/00"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. 256 ranges of /8, each
# allowed alone, together cover every IPv4 address.
run "refuses_ranges_covering_every_ipv4_address" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = [for i in range(256) : "${i}.0.0.0/8"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

# The address guard refuses this list unless the unsafe opt-in is set. An entry with a space after
# it is not a plain CIDR range.
run "refuses_trailing_space" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["0.0.0.0/0 "]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}
