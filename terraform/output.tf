output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.lab.kube_config[0].raw_config
  sensitive = true
}