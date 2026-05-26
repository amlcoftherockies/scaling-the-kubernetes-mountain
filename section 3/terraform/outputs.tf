output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "The name of the GKE cluster."
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "The Kubernetes API server endpoint."
}

output "kubeconfig_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.gcp_zone} --project ${var.gcp_project_id}"
  description = "Copy and run this command on your local machine to fetch the kubeconfig and connect to the cluster."
}
