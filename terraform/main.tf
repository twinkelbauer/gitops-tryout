# Feste Version-Slugs (z.B. "1.36.3-do.5") werden von DO irgendwann zurückgezogen
# und lassen dann jeden frischen Apply scheitern — daher dynamisch auflösen.
data "digitalocean_kubernetes_versions" "current" {
  version_prefix = "1.36."
}

resource "digitalocean_kubernetes_cluster" "lab" {
  name    = "lab"
  region  = "fra1"
  version = data.digitalocean_kubernetes_versions.current.latest_version

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

# Die Ingress-LB bekommt bei jedem Neuaufbau eine neue IP. Wir lesen sie über
# die DO-API (nicht über den kubernetes-Provider — der ist bei einem frischen
# Apply zur Plan-Zeit noch nicht konfigurierbar). Helms wait=true garantiert,
# dass der LB samt IP existiert, sobald ingress-nginx fertig installiert ist.
data "digitalocean_loadbalancer" "ingress" {
  name       = "lab-ingress"
  depends_on = [helm_release.ingress_nginx]
}

locals {
  lb_ip = data.digitalocean_loadbalancer.ingress.ip
}

# App-of-Apps: Terraform legt nur die Root-Application an; die eigentlichen
# Apps liegen als Helm-Templates in charts/apps/ im Git-Repo. Die LB-IP wird
# als Helm-Parameter durchgereicht, damit in Git keine IPs gepflegt werden.
# depends_on prometheus: die podinfo-Charts enthalten einen ServiceMonitor,
# dessen CRD erst mit kube-prometheus-stack in den Cluster kommt.
resource "kubectl_manifest" "root_app" {
  yaml_body = templatefile("${path.module}/../apps/root.yaml.tftpl", {
    lb_ip = local.lb_ip
  })
  depends_on = [helm_release.argocd, helm_release.prometheus]
}