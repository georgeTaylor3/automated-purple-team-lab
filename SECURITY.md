# Security Policy

## What this lab is for

This lab is for testing security detections and automation.

The attack activity in this project should only run against systems that are
part of this lab.

Nothing in this project should be used against systems I do not own or have
permission to test.

## Public demo

The public demo will let a user run a small number of pre-built test scenarios.

Users will not be able to enter their own commands or targets.

They will not be able to choose:

- IP addresses
- domains
- shell commands
- payloads
- CALDERA abilities
- CALDERA agents
- CALDERA operations

The demo site will only accept known scenario names that I have already set up.

For example:

    linux-discovery

The backend will map that name to the correct test in CALDERA.

## Things that should never be in this repo

Do not commit:

- passwords
- API keys
- access tokens
- private keys
- cloud credentials
- service account keys
- Elastic credentials
- CALDERA credentials
- SSH private keys
- recovery codes
- real .env files
- Terraform state that contains sensitive information

## Internet access

Only parts of the lab that are meant to be public should be exposed to the
internet.

The following should stay private:

- CALDERA
- CALDERA API
- Elasticsearch management interfaces
- test machines
- SSH
- admin interfaces
- internal APIs

## Accounts and permissions

Admin accounts and service accounts should be separate.

My admin accounts will use MFA and hardware security keys where possible.

Automation will use its own service accounts and API credentials with only the
permissions it needs.

The public demo account will have very limited permissions.

## Scope

All attack simulations must stay inside the lab.

The project is being built for:

- security testing
- detection engineering
- automation
- learning
- purple-team testing
- demonstrations
