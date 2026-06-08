terraform {
  required_version = ">= 1.10.1"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.60.1"
    }
  }
}

locals {
  kube_hetzner_module_source  = "kube-hetzner/kube-hetzner/hcloud"
  kube_hetzner_module_version = "2.19.3"
  hcloud_provider_minimum     = ">= 1.59.0"
  production_remote_state     = true
}
