# examples/mllp-only

**Shape:** MLLP only over TCP ingress.

Pathways taking HL7 v2 over MLLP, on three TCP ports, from senders outside your network, and nothing else.

## What it builds

- The module as in the basic example, with `internal_load_balancer_enabled = false`: the environment gets a public address.
- TCP ingress on 2575 (the main port), 2576 and 2577 (additional port mappings), reachable only from the senders' named ranges; every other address is denied.
- No HTTP ingress, no storage account and no SFTP.

## When to choose it

Your senders reach you over the internet, cannot use a VPN or ExpressRoute into your network, and speak only MLLP.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- Data transfer in from the senders and out to them.

## What it does not cover

- MLLP has no authentication of its own. The address guard is the only check the platform makes: require mutual TLS on each MLLP source in your project as well.
- We prefer a private connection to a public address: the [internal only example](../internal-only) is that shape.
- Container Apps takes at most six TCP ports per app, and each port once per environment.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
