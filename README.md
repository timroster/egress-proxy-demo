# Egress Proxy Demo

Demonstration Terraform code to create one VPCs, and multiple subnets. One subnet will act as a **Transit** subnet which provides internal connectivity using a [ZeroTier VNF](https://github.com/timroster/terraform-vsi-zerotier-edge.git). Due to some routing complexities, the **Transit** subnet approach is currently using a single zone. There is a Floating IP address associated with the VNF instance and a restrictive security group allowing only the transport protocol of the ZeroTier network inbound.

Another set of subnets will be the **Egress** subnets. These subnets will have application layer (HTTP tunnel) proxies running squid on ubuntu servers. The security group applied to the interaces of the proxies is restrictive on inbound private network traffic and permissive to the Internet. Each **Egress** subnet is associated with a VPC Public Gateway.

A Red Hat OpenShift cluster will be hosted on a third subnet zone. This **Cluster** subnet will not have any hosts with Floating IP addresses assigned and no VPC Public Gateway. The OpenShift cluster will be deployed with private only endpoints and after it is configured with an internal ingress, a module will run to configure the cluster and workers to use the application proxy in the **Egress** subnet for Internet access.

Input variables to the code (see `example.tfvars`)

* IBM Cloud API Key - provide this to allow internal operations (API calls) of the modules in the target account
* IBM Cloud region for creating the deployment
* Name of a public ssh that has been added to the VPC service in the region for the deployment
* Name of the resource group for the deployment
* A prefix to use for all resources
* The ZeroTier network ID - can be pre-existing with workstations for users already enrolled
* The ZeroTier network CIDR - virtual LAN addresses that all ZeroTier clients are addressed from
