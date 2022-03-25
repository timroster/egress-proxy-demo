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

module "logdna" {
  source = "github.com/cloud-native-toolkit/terraform-ibm-logdna.git"

  resource_group_name      = var.resource_group_name
  region                   = var.region
  provision                = false
  name                     = var.logdna_name
}

module "cluster" { 
  source = "github.com/cloud-native-toolkit/terraform-ibm-ocp-vpc.git"

  resource_group_name = module.resource_group.name
  region              = var.region
  ibmcloud_api_key    = var.ibmcloud_api_key
  name                = var.cluster_name
  worker_count        = var.worker_count
  exists              = true
  name_prefix         = ""
  vpc_name            = ""
  vpc_subnets         = []
  vpc_subnet_count    = var.cluster_subnet_count
  cos_id              = ""
}
resource "ibm_resource_key" "resourceKey" {
  name                 = "LogDNAKey-01"
  resource_instance_id = module.logdna.id
  role                 = "Manager"
}

resource "ibm_ob_logging" "test-logdna" {
  depends_on  = [ibm_resource_key.resourceKey]
  cluster     = module.cluster.id
  instance_id = module.logdna.guid
  private_endpoint = true
}


