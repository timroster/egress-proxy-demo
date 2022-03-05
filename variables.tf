variable "resource_group_name" {
  type        = string
  description = "The name to use for the resource group"
}

variable "region" {
  type        = string
  description = "The IBM Cloud region where the environment will be created"
}

variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud api token"
}

variable "name_prefix" {
  type        = string
  description = "The prefix for resource names"
}

variable "transit_subnet_count" {
  type        = number
  description = "The prefix for resource names"
  default     = 1
}

variable "egress_subnet_count" {
  type        = number
  description = "The prefix for resource names"
  default     = 1
}

variable "cluster_subnet_count" {
  type        = number
  description = "The prefix for resource names"
  default     = 1
}

variable "worker_count" {
  type        = number
  description = "The number of workers in the OpenShift cluster"
  default     = 2
}

variable "worker_flavor" {
  type        = string
  description = "Profile to use for cluster workers"
  default     = "bx2.4x16"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of existing SSH key ID to inject into the virtual server instance"
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Tags that should be added to the resources"
}

variable "zt_network" {
  type = string

  validation {
    condition     = length(var.zt_network) == 16
    error_message = "The zt_network id must be be 16 characters long."
  }
}

variable "zt_network_cidr" {
  type        = string
  description = "Native LAN on Zerotier for connecting endpoints"
  default     = "192.168.192.0/24"
}
