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

variable "ssh_key_name" {
  type        = string
  description = "Name of existing SSH key ID to inject into the virtual server instance"
}

variable "logdna_name" {
  type        = string
  description = "Name of existing logdna instance"
}

variable "cluster_name" {
  type        = string
  description = "Name of existing cluster"
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

variable "tags" {
  type        = list(string)
  default     = []
  description = "Tags that should be added to the resources"
}