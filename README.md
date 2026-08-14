# Automated Purple Team Lab

A cloud-hosted cybersecurity automation project designed to demonstrate
controlled adversary emulation, centralized security telemetry, detection
engineering, and automated detection validation.

## Project Objective

The lab will provide a controlled purple-team workflow:

1. A user selects an approved adversary-emulation scenario.
2. A secure demo controller validates the request.
3. MITRE CALDERA executes the predefined scenario against an isolated
   project-owned target.
4. Endpoint and application telemetry is forwarded to Elastic Security.
5. Detection rules analyze the resulting activity.
6. Kibana displays events and security alerts.
7. Automated validation confirms whether the expected telemetry and
   detections occurred.

## Portfolio Skills Demonstrated

This project is intended to demonstrate practical experience with:

- cloud security architecture
- Infrastructure as Code
- Terraform
- configuration automation
- Linux administration
- cloud IAM
- workload identities
- hardware-backed administrator authentication
- centralized logging
- Elastic Security
- SIEM engineering
- detection engineering
- MITRE ATT&CK
- MITRE CALDERA
- adversary emulation
- security automation
- API security
- least privilege
- secrets management
- automated security validation
- secure public demo design

## Security Model

The public demonstration will not permit arbitrary:

- commands
- targets
- IP addresses
- payloads
- shell arguments
- CALDERA abilities
- CALDERA agents
- network destinations

Visitors will be permitted to select only predefined simulation scenarios.

CALDERA, administrative interfaces, target systems, Elasticsearch management
interfaces, and other privileged services will remain isolated from direct
public access.

## Administrative Authentication

Administrative access will use strong MFA and, where supported, hardware-backed
authentication using a YubiKey.

Public demonstration users will use a separate restricted authentication model
and will never inherit administrative privileges.

## Status

Phase 1: repository and security architecture development.
