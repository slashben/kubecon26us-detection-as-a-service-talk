variable "cluster_name" {
  description = "DOKS cluster name. 02-bootstrap looks the cluster up by this name."
  type        = string
  default     = "dac-demo"
}

variable "region" {
  description = "DigitalOcean region slug for the VPC and cluster."
  type        = string
  default     = "nyc3"
}

variable "kubernetes_version_prefix" {
  description = "Minor version prefix; the latest DOKS patch release matching it is used."
  type        = string
  default     = "1.36."
}

variable "node_size" {
  description = "Droplet size slug for the node pool."
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "node_count" {
  description = "Number of nodes in the default pool."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags applied to the cluster and node pool. 'donotdelete' keeps the cluster out of nightly cleanup jobs that honour it."
  type        = list(string)
  default     = ["donotdelete", "dac-demo"]
}
