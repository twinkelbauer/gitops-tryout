output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.lab.kube_config[0].raw_config
  sensitive = true
}

output "dev_url" {
  value = "http://dev.${local.lb_ip}.sslip.io"
}

output "stage_url" {
  value = "http://stage.${local.lb_ip}.sslip.io"
}

output "argocd_password_hint" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}