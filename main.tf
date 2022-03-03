provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

data "ibm_is_ssh_key" "existing" {
  name = var.ssh_key_name
}

module "vpcssh" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-vpc-ssh.git"

  resource_group_name = module.resource_group.name
  name_prefix         = var.name_prefix
  public_key          = ""
  private_key         = ""
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
}

module "cos" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-object-storage.git"

  resource_group_name = var.resource_group_name
  name_prefix         = var.name_prefix
  tags                = var.tags
}

module "cluster" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-ocp-vpc.git"

  resource_group_name     = var.resource_group_name
  region                  = var.region
  ibmcloud_api_key        = var.ibmcloud_api_key
  worker_count            = 2
  name_prefix             = var.name_prefix
  vpc_name                = module.vpc.name
  vpc_subnet_count        = var.cluster_subnet_count
  vpc_subnets             = module.cluster_subnet.subnets
  cos_id                  = module.cos.id
  login                   = true
  disable_public_endpoint = true
}

module "ocp_proxy_module" {
  depends_on = [ module.cluster ]

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
