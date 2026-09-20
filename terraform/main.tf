resource "digitalocean_kubernetes_cluster" "lab" {
  name    = "lab"
  region  = "fra1"
  version = "1.36.3-do.5"

  node_pool {
    name       = "worker"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3"
  namespace        = "ingress-nginx"
  create_namespace = true

  wait    = true
  timeout = 600

  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
    value = "lab-ingress"
  }
}