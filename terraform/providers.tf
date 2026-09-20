locals {
  kubeconfig = digitalocean_kubernetes_cluster.lab.kube_config[0]
}

provider "helm" {
  kubernetes {
    host                   = local.kubeconfig.host
    token                  = local.kubeconfig.token
    cluster_ca_certificate = base64decode(local.kubeconfig.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = local.kubeconfig.host
  token                  = local.kubeconfig.token
  cluster_ca_certificate = base64decode(local.kubeconfig.cluster_ca_certificate)
  load_config_file       = false
}

provider "digitalocean" {
  token = var.do_token
}
