output "kubeconfig_path" {
  description = "Path where kube-hetzner writes kubeconfig after apply. The file is operational secret material and must not be committed."
  value       = coalesce(var.kubeconfig_path, "./${var.cluster_name}_kubeconfig.yaml")
}

output "cluster_name" {
  description = "kube-hetzner cluster name."
  value       = var.cluster_name
}

output "node_pool_names" {
  description = "Control-plane and worker node pool names used by this stack."
  value = {
    control_plane = [for pool in local.control_plane_nodepools : pool.name]
    workers       = [for pool in local.agent_nodepools : pool.name]
  }
}

output "default_storage_class" {
  description = "Default Hetzner CSI StorageClass expected for runner PVCs."
  value       = local.default_storage_class
}
