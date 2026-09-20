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

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.9.2"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600
}

resource "helm_release" "prometheus" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "91.4.0"
  namespace        = "monitoring"
  create_namespace = true

  wait    = true
  timeout = 600
}

# Die Ingress-LB bekommt bei jedem Neuaufbau eine neue IP. Wir lesen sie hier
# aus und leiten daraus die sslip.io-Hostnamen ab, statt IPs zu pflegen.
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}

locals {
  lb_ip = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
}

resource "kubectl_manifest" "podinfo_dev" {
  yaml_body = templatefile("${path.module}/../apps/dev.yaml.tftpl", {
    host = "dev.${local.lb_ip}.sslip.io"
  })
  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "podinfo_stage" {
  yaml_body = templatefile("${path.module}/../apps/stage.yaml.tftpl", {
    host = "stage.${local.lb_ip}.sslip.io"
  })
  depends_on = [helm_release.argocd]
}