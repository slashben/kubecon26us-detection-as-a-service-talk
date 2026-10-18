output "cluster_name" {
  value = digitalocean_kubernetes_cluster.demo.name
}

output "cluster_id" {
  value = digitalocean_kubernetes_cluster.demo.id
}

output "kubernetes_version" {
  value = digitalocean_kubernetes_cluster.demo.version
}
