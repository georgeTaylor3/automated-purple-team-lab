# Network Topology

This diagram represents the current network design and the planned placement of
the CALDERA control and target workloads.

The workload nodes are marked as planned because the Compute Engine instances
have not been created yet.

```mermaid
flowchart TB
    internet["Public Internet"]
    kms["Google Windows KMS (35.190.247.13/32)"]

    subgraph gcp["Google Cloud"]
        subgraph vpc["purple-team-vpc"]

            router["Cloud Router (purple-team-router)"]
            nat["Cloud NAT (control-cloud-nat)"]

            subgraph control["Control subnet (10.60.10.0/24)"]
                caldera["Planned CALDERA control VM (caldera-control-sa)"]
            end

            subgraph server["Server target subnet (10.60.20.0/24)"]
                web["Planned Linux web server (web-target-sa)"]
            end

            subgraph workstation["Workstation subnet (10.60.30.0/24)"]
                windows["Planned Windows endpoint (workstation-target-sa)"]
            end

        end
    end

    router -. "NAT control plane" .-> nat

    caldera -->|"TCP 443 only"| nat
    nat -->|"Public NAT"| internet

    web -->|"TCP 8888 CALDERA C2"| caldera
    windows -->|"TCP 8888 CALDERA C2"| caldera

    windows -->|"TCP 443 business flow"| web

    windows -->|"TCP 1688 activation / renewal"| kms

    caldera -. "New connections denied" .-> web
    caldera -. "New connections denied" .-> windows

    web -. "General Internet egress denied; no Cloud NAT" .-> internet
    windows -. "General Internet egress denied; no Cloud NAT" .-> internet

## Current trust rules

- The target can initiate CALDERA C2 traffic on TCP 8888.
- Other target-to-control traffic is denied.
- CALDERA may not initiate new connections into the target subnet.
- CALDERA may initiate outbound HTTPS connections on TCP 443.
- Other CALDERA egress is denied.
- The control subnet is included in Cloud NAT.
- The target subnet is not included in Cloud NAT.
- Neither workload will receive a public VM address.
