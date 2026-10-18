data "digitalocean_kubernetes_versions" "selected" {
  version_prefix = var.kubernetes_version_prefix
}

resource "digitalocean_vpc" "demo" {
  name   = "${var.cluster_name}-vpc"
  region = var.region
}

resource "digitalocean_kubernetes_cluster" "demo" {
  name     = var.cluster_name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.selected.latest_version
  vpc_uuid = digitalocean_vpc.demo.id
  tags     = var.tags

  node_pool {
    name       = "default"
    size       = var.node_size
    node_count = var.node_count
    tags       = var.tags
  }
}
