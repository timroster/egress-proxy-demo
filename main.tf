provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

data "ibm_is_ssh_key" "existing" {
  name = var.ssh_key_name
}

module "resource_group" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-resource-group.git"

  resource_group_name = var.resource_group_name
  provision           = false
}

module "vpc" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-vpc.git"

  resource_group_name = module.resource_group.name
  region              = var.region
  name_prefix         = var.name_prefix
}

module "gateways" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-vpc-gateways.git"

  resource_group_id = module.resource_group.id
  region            = var.region
  vpc_name          = module.vpc.name
  provision         = true
}

module "transit_subnet" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-vpc-subnets.git"

  resource_group_name = var.resource_group_name
  vpc_name            = module.vpc.name
  _count              = var.transit_subnet_count
  region              = var.region
  label               = "transit"
  provision           = true
  acl_rules = [{
    name        = "inbound-zt",
    action      = "allow",
    direction   = "inbound",
    source      = "0.0.0.0/0",
    destination = "10.0.0.0/8",
    udp = {
      port_min = 9993,
      port_max = 9993,
      source_port_min = 1,
      source_port_max = 65535,
    }
  },{
    name        = "outbound-zt-udp",
    action      = "allow",
    direction   = "outbound",
    source      = "10.0.0.0/8",
    destination = "0.0.0.0/0",
    udp = {
      port_min = 1,
      port_max = 65535,
      source_port_min = 1,
      source_port_max = 65535,
    }
  },{
    name        = "outbound-zt-tcp",
    action      = "allow",
    direction   = "outbound",
    source      = "10.0.0.0/8",
    destination = "0.0.0.0/0",
    tcp = {
      port_min = 1,
      port_max = 65535,
      source_port_min = 1,
      source_port_max = 65535,
    }
  },{
    name        = "inbound-zt-https-reply",
    action      = "allow",
    direction   = "inbound",
    source      = "0.0.0.0/0",
    destination = "10.0.0.0/8",
    tcp = {
      port_min = 1,
      port_max = 65535,
      source_port_min = 443,
      source_port_max = 443,
    }
  },{
    name        = "inbound-zt-http-reply",
    action      = "allow",
    direction   = "inbound",
    source      = "0.0.0.0/0",
    destination = "10.0.0.0/8",
    tcp = {
      port_min = 1,
      port_max = 65535,
      source_port_min = 80,
      source_port_max = 80,
    }
  },{
    name = "internal-zt-traffic-in",
    action = "allow",
    direction = "inbound",
    source = "10.0.0.0/8",
    destination = var.zt_network_cidr
  },{
    name = "internal-zt-traffic-out",
    action = "allow",
    direction = "outbound",
    source = var.zt_network_cidr,
    destination = "10.0.0.0/8"
  }]
}

module "egress_subnet" {
  depends_on = [ module.transit_subnet ]
    
  source = "github.com/cloud-native-toolkit/terraform-ibm-vpc-subnets.git"

  resource_group_name = var.resource_group_name
  vpc_name            = module.vpc.name
  gateways            = module.gateways.gateways
  _count              = var.egress_subnet_count
  region              = var.region
  label               = "egress"
  provision           = true
}

module "cluster_subnet" {
  depends_on = [ module.transit_subnet, module.egress_subnet ]

  source = "github.com/cloud-native-toolkit/terraform-ibm-vpc-subnets.git"

  resource_group_name = var.resource_group_name
  vpc_name            = module.vpc.name
  _count              = var.cluster_subnet_count
  region              = var.region
  label               = "cluster"
  provision           = true
}

module "proxy" {   
  source = "github.com/timroster/terraform-vsi-proxy.git"

  resource_group_name = var.resource_group_name
  region              = var.region
  ibmcloud_api_key    = var.ibmcloud_api_key
  ssh_key_id          = data.ibm_is_ssh_key.existing.id
  vpc_name            = module.vpc.name
  vpc_subnet_count    = var.egress_subnet_count
  vpc_subnets         = module.egress_subnet.subnets
  allow_ssh_from      = var.zt_network_cidr
  tags                = var.tags
}

module "zerotier-vnf" {
  source = "github.com/timroster/terraform-vsi-zerotier-edge.git"

  resource_group_id = module.resource_group.id
  region            = var.region
  ibmcloud_api_key  = var.ibmcloud_api_key
  ssh_key_id        = data.ibm_is_ssh_key.existing.id
  vpc_name          = module.vpc.name
  vpc_subnet_count  = var.transit_subnet_count
  vpc_subnets       = module.transit_subnet.subnets
  create_public_ip  = true
  zt_network        = var.zt_network
  tags              = var.tags
}

## Send some traffic over zerotier network to make sure routes discovered
resource "null_resource" "open_zerotier" {
  depends_on = [module.zerotier-vnf]

  provisioner "local-exec" {
    command = "sleep 180 && ping -c 60 $ZTVNF"
    # command = "ping -c 1 $ZTVNF"
  
    environment = {
      ZTVNF = module.zerotier-vnf.private_ips[0]
    }
  }
}

## TODO - fix routing priority in ZT VNF module to support multizone until then:
# add route to ZeroTier network through VSI if there are > 1 cluster subnet
locals {
    name = "${replace(module.vpc.name, "/[^a-zA-Z0-9_\\-\\.]/", "")}-zerotier"
}

data "ibm_is_vpc_default_routing_table" "vpc_route" {
  vpc = module.vpc.id
}

resource "ibm_is_vpc_routing_table_route" "zt_ibm_is_vpc_routing_table_route" {
  count = var.cluster_subnet_count > 1 ? (var.cluster_subnet_count - 1) : 0

  vpc           = module.vpc.id
  routing_table = data.ibm_is_vpc_default_routing_table.vpc_route.id
  zone          = module.cluster_subnet.subnets[count.index+1].zone
  name          = "${local.name}${format("%02s", count.index+1)}-ztgw"
  destination   = var.zt_network_cidr
  action        = "deliver"
  next_hop      = module.zerotier-vnf.private_ips[0]
}
##


module "cos" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-object-storage.git"

  resource_group_name = var.resource_group_name
  name_prefix         = var.name_prefix
  tags                = var.tags
}

module "cluster" {
  # if there's some problem with zerotier networking don't incurr time penalty to provision cluster
  depends_on = [ null_resource.open_zerotier, null_resource.cleanup ]
    
  source = "github.com/cloud-native-toolkit/terraform-ibm-ocp-vpc.git"

  resource_group_name     = var.resource_group_name
  region                  = var.region
  ibmcloud_api_key        = var.ibmcloud_api_key
  worker_count            = var.worker_count
  flavor                  = var.worker_flavor
  name_prefix             = var.name_prefix
  vpc_name                = module.vpc.name
  vpc_subnet_count        = var.cluster_subnet_count
  vpc_subnets             = module.cluster_subnet.subnets
  cos_id                  = module.cos.id
  force_delete_storage    = true
  login                   = true
  disable_public_endpoint = true
  tags                    = var.tags
}

module "ocp_proxy_module" {
  depends_on = [ module.cluster, module.zerotier-vnf, module.proxy ]

  source = "github.com/timroster/terraform-ocp-proxyconfig.git"

  ibmcloud_api_key    = var.ibmcloud_api_key
  resource_group_name = module.resource_group.name
  region              = var.region
  proxy_endpoint      = module.proxy.proxy_endpoint
  cluster_config_file = module.cluster.platform.kubeconfig
  cluster_name        = module.cluster.name
  roks_cluster        = true
}

output "proxy_endpoint" {
  value = module.proxy.proxy_endpoint
}

## clean out some bits left by cluster resource provision
resource "null_resource" "cleanup" {

  provisioner "local-exec" {
  when = destroy
    command = "rm -rf .kube .tmp bin2"
  }

}
