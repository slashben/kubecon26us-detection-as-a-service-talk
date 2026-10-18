provider "digitalocean" {}

data "digitalocean_kubernetes_cluster" "demo" {
  name = var.cluster_name
}

locals {
  kubeconfig = data.digitalocean_kubernetes_cluster.demo.kube_config[0]
}

provider "kubernetes" {
  host                   = local.kubeconfig.host
  token                  = local.kubeconfig.token
  cluster_ca_certificate = base64decode(local.kubeconfig.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = local.kubeconfig.host
    token                  = local.kubeconfig.token
    cluster_ca_certificate = base64decode(local.kubeconfig.cluster_ca_certificate)
  }
}
