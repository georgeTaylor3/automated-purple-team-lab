# Firewall Trust Model

The project separates control-side workloads from target (web abd workstation)  workloads and
allows communication only when required.

The initial firewall policy is built around 2 workload identities:

- `caldera-control-sa` for the CALDERA control workload
- `web-target-sa, workstation-target-sa` for target systems that emulate business workloads

These service accounts are attached to planned Compute Engine workloads and are
used as firewall selectors. They are not used by the workloads to log into one
another.

The service accounts do not have user-managed service account keys.

In general, I try to make a good linear logic flow, so that it wasy to follow up the priority. 
I prioritize the legable flow here as it helps add/ restrict further workload actions later.
If there is a benefit to combining objects (ip ranges + workload identities), i will figure it
out later. 

## Network zones

The control subnet is:

    10.60.10.0/24

The target subnet is:

    10.60.20.0/24

The control and target networks are intentionally treated as separate trust
zones even though they are part of the same VPC.

## CALDERA communication

The initial CALDERA communication model allows a vm in target workloads to initiate
a connection to the CALDERA control workload on TCP port 8888.

The intended flow is:

    web-target-sa, workstation-target-sa
            |
            | TCP 8888
            v
    caldera-control-sa

The target initiates the connection.

Traffic leaving the target is egress from the target workload. The same traffic
arriving at CALDERA is ingress to the CALDERA workload.

## Firewall rules

### allow-target-to-caldera-c2

Direction: ingress

This rule allows TCP port 8888 into workloads using `caldera-control-sa` when
the traffic originates from a workload using `web-target-sa, workstation-target-sa`.

The service accounts identify the workloads participating in the connection.

### allow-target-to-caldera-c2-egress

Direction: egress

This rule allows workloads using `web-target-sa, workstation-target-sa` to send TCP port 8888
traffic toward the control subnet.

It has priority 1000 so this specific exception is evaluated before the broader
target-to-control deny rule.

### deny-target-to-control

Direction: egress

This rule denies other traffic from workloads using `web-target-sa, workstation-target-sa` toward
the control subnet.

It has priority 2000.

The result is:

    target -> control TCP 8888        allow
    target -> control other traffic   deny

Future required traffic will receive its own specific rule rather than
modifying this exception. this will help organize the rules (good linear logic flow).

### deny-caldera-to-target

Direction: egress

This rule prevents workloads using `caldera-control-sa` from initiating
arbitrary new connections toward the target subnet.

Replies belonging to an already established target-initiated connection are
handled by the stateful VPC firewall memory.

If a future simulation requires CALDERA to initiate a specific connection to a
target, the port/protocal will be addaded as a separate allow rule (again for good linear flow).

## Firewall logging

Logging is enabled for the initial firewall rules.

firewall metadata is currently excluded to reduce log volume.
Logging settings can be revisited when network telemetry is integrated
with the monitoring and detection portions of the lab.

## IAM boundary

Terraform manages firewall rules by impersonating the dedicated
`terraform-deployer` service account.

A project-level custom role named `terraformFirewallManager` provides the
firewall management permissions needed by Terraform instead of granting the
broader Compute Security Admin role.

The custom role contains firewall create, read, list, update, and delete
permissions.

Terraform also has Service Account User permission directly on
`caldera-control-sa` and `web-target-sa, workstation-target-sa`. These grants are scoped to the
individual workload service accounts rather than the entire project.

The workload service accounts themselves currently have no project-level IAM
roles.

## Current limitations

There are no Compute Engine workloads using these service accounts yet.

As a result, the service-account-based firewall rules currently have no VM
instances to match.

The current firewall policy also does not allow:

- public SSH or RDP
- public CALDERA access
- general Internet connectivity
- Cloud NAT
- Elastic telemetry paths
- administrative management paths

Those will be allowed when the resource or function is necessary.
