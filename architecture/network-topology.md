# Network Topology

This diagram represents the current network design and the planned placement of
the CALDERA control and purple-team target workloads.

The workload nodes are marked as planned because the Compute Engine instances
have not been created yet.

```mermaid
flowchart TB
    internet["Public Internet"]

    subgraph gcp["Google Cloud"]
        subgraph vpc["purple-team-vpc"]

            router["Cloud Router<br/>purple-team-router"]
            nat["Cloud NAT<br/>control-cloud-nat"]

            subgraph control["Control subnet
            10.60.10.0/24"]
                caldera["Planned CALDERA control VM<br/>Service account: caldera-control-sa"]
            end

            subgraph target["Target subnet
            10.60.20.0/24"]
                purple["Planned purple-team target VM<br/>Service account: purple-target-sa"]
            end

        end
    end

    router -. "NAT control plane" .-> nat

    caldera -->|"TCP 443 allowed"| nat
    nat -->|"Public NAT"| internet

    purple -->|"TCP 8888 allowed"| caldera

    caldera -. "New connections denied" .-> purple
    purple -. "No general Internet egress" .-> internet
```

## Current trust rules

- The target can initiate CALDERA C2 traffic on TCP 8888.
- Other target-to-control traffic is denied.
- CALDERA may not initiate new connections into the target subnet.
- CALDERA may initiate outbound HTTPS connections on TCP 443.
- Other CALDERA egress is denied.
- The control subnet is included in Cloud NAT.
- The target subnet is not included in Cloud NAT.
- Neither workload will receive a public VM address.
