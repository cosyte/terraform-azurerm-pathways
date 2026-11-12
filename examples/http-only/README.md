# examples/http-only

**Shape:** HTTP only.

Pathways taking messages over HTTP only, such as FHIR or HL7 v2 posted by an application on your network, behind HTTP ingress that ends TLS.

## What it builds

- The module with `http_port = 8080` and no MLLP port: the app gets HTTP ingress. Container Apps ends TLS on port 443 of the app's address and passes plain HTTP to the engine's HTTP source on 8080; plain HTTP from outside the environment is refused, and only `10.20.0.0/16` gets through.
- A private DNS zone named for the environment's default domain, with a record for every name in it pointing at the environment's static address, linked to the virtual network, so clients there resolve the app's name.
- The identity, the workspace, the Key Vault and the database, as in the basic example.

## When to choose it

Your clients post messages over HTTPS and nothing sends MLLP: FHIR, HL7 v2 over HTTP, or an application's webhook.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- The private DNS zone, by the month, and the queries it answers.

## What it does not cover

- MLLP beside HTTP: an app takes one or the other in this release of the module.
- Your own domain name and certificate: clients use the app's address in the environment's default domain.
- Who may post: the address guard admits a range, and the HTTP source's own settings decide what it accepts.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
