output "cluster_name" {
  value       = oci_containerengine_cluster.this.name
  description = "The name of your OKE cluster."
}

output "compartment_ocid" {
  value       = local.compartment_id
  description = "YOUR compartment. Section 6 reads this to create your registry repository."
}

output "compartment_name" {
  value = "lab:${local.compartment_name}"
}

output "cluster_id" {
  value       = oci_containerengine_cluster.this.id
  description = "The OCID of your OKE cluster."
}

output "kubernetes_version" {
  value = local.k8s_version
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at your cluster."
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.this.id} --file $HOME/.kube/config --region ${var.region} --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT --profile ${var.oci_profile}"
}
