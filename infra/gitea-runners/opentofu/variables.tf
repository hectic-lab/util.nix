variable "hcloud_token" {
  description = "Hetzner Cloud API token for kube-hetzner. Set with TF_VAR_hcloud_token or secret injection only; never commit it. kube-hetzner may place this value into Kubernetes secret resources/state, so scan plans before apply."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key installed on cluster nodes. Supply from an external file or secret injection path."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key used by kube-hetzner during bootstrap. Supply from an external file or secret injection path; never commit it."
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name for the kube-hetzner runner cluster."
  type        = string
  default     = "gitea-runners"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name must contain only lowercase letters, numbers, and dashes."
  }
}

variable "hetzner_location" {
  description = "Hetzner Cloud location for all node pools. fsn1 keeps the first runner cluster in Falkenstein."
  type        = string
  default     = "fsn1"
}

variable "network_region" {
  description = "Hetzner private network region. eu-central covers fsn1."
  type        = string
  default     = "eu-central"
}

variable "control_plane_server_type" {
  description = "Default control-plane server type. cpx21 is small but leaves headroom for kube-system workloads."
  type        = string
  default     = "cpx21"
}

variable "worker_server_type" {
  description = "Default worker server type for the initial trusted DinD runner pool. Three cpx31 workers provide enough headroom for five privileged jobs before Task 11 scaling validation."
  type        = string
  default     = "cpx31"
}

variable "worker_count" {
  description = "Fixed worker count. Increase to 5 or choose a larger worker_server_type later to target 10 concurrent DinD jobs; do not enable autoscaling in this stack."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "kubeconfig_path" {
  description = "Expected kubeconfig path. kube-hetzner v2.19.3 writes this as <cluster_name>_kubeconfig.yaml when create_kubeconfig is true."
  type        = string
  default     = null
}

variable "base_domain" {
  description = "Optional base domain for node reverse DNS. Empty keeps kube-hetzner defaults."
  type        = string
  default     = ""
}
