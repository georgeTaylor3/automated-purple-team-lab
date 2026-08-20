# Egress and Cloud NAT

The lab uses restricted outbound connectivity rather than assigning public IP
addresses directly to Compute Engine workloads.

## Design goals

The CALDERA control workload needs limited outbound Internet connectivity for
initial provisioning, software updates, installation, and required external
dependencies. further on I will introduce firewall allow when a maintenance
period is needed. Then eventually I will host all required update management
functions internally.

The purple-team target does not require general Internet access.

I will never use public IP address bound to a VM. There is no need with modern
routing/fw/proxy functions/devices.

## CALDERA control egress

Workloads using `caldera-control-sa` may initiate outbound TCP port 443
connections.

This permission exists for provisioning, updates, and required HTTPS
dependencies. It is not required for the target-to-CALDERA C2 connection.

Other CALDERA egress is denied unless a higher-priority firewall rule
explicitly allows it.

Connections initiated by CALDERA toward the target subnet are denied by a
higher-priority firewall rule.

The current HTTPS allowance is the initial operating model for the lab. It is
not intended to be the final egress security posture.

After the lab is functioning reliably, outbound Internet access should be
reduced further.

Possible future controls include:

- maintenance-only Internet access
- destination-restricted HTTPS
- a managed secure web proxy
- internally hosted package repositories
- internally hosted artifact repositories

## Target workload egress

Workloads using `purple-target-sa` may initiate CALDERA C2 traffic on TCP port
8888.

Other traffic toward the control subnet is denied.

All other target egress is denied unless a higher-priority firewall rule
explicitly allows it.

The target subnet is not included in the Cloud NAT configuration.

This provides two independent controls against general target Internet access:

1. The target workload has a default-deny egress firewall policy.
2. The target subnet has no Public Cloud NAT path.

## Cloud NAT

The lab uses a regional Cloud Router and Public Cloud NAT for outbound
connectivity from the control subnet.

The NAT configuration uses an explicit subnet list rather than automatically
including every subnet in the region.

applied only to control subnet.

target subnet has not defined nat so it is excluded

NAT addresses are automatically allocated because the lab does not currently
require a fixed public egress address.

NAT error logging is enabled. Successful translations are not currently logged
to reduce log volume.

## Security model

Cloud NAT provides address translation. It does not evaluate rules for outbound
traffic. i.e. the router routs the firewall rules assess if the packets can go
to a place.

VPC firewall rules determine which traffic a workload may initiate before that
traffic can use the NAT path.

The resulting control path is:

    workload
        |
        v
    egress firewall
        |
        v
    routing
        |
        v
    Cloud NAT
        |
        v
    Internet

Public Cloud NAT does not make the private workload directly reachable through
unsolicited inbound Internet connections.

## Current egress policy

The current control workload policy is:

    CALDERA -> target subnet
        DENY

    CALDERA -> TCP 443
        ALLOW

    CALDERA -> other destinations and protocols
        DENY

The current target workload policy is:

    target -> CALDERA TCP 8888
        ALLOW

    target -> other control-subnet traffic
        DENY

    target -> all other egress
        DENY

The target subnet also has no Cloud NAT path.

## Future hardening

The initial design intentionally permits the CALDERA workload outbound HTTPS so
the lab can be built/maintained without first creating an internal software
distribution environment.

Once the lab is stable, this permission will be revisited.

The intended progression is:

    Phase A
        CALDERA may use outbound HTTPS.

    Phase B (later)
        General Internet access is reduced or limited to maintenance periods
        and approved destinations.

    Phase C (lllater)
        Package, source, and artifact dependencies may be hosted internally so
        arbitrary Internet egress can be removed.
