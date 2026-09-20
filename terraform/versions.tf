terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm",
      version = "~> 2.12"
    }
    kubectl = {
      source  = "alekc/kubectl",
      version = "~> 2.1"
    }
  }
}
