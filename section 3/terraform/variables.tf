variable "gcp_project_id" {
  type        = string
  description = "The GCP Project ID where the GKE cluster will be provisioned."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region to deploy the cluster to."
  default     = "us-central1"
}

variable "gcp_zone" {
  type        = string
  description = "The GCP zone within the region."
  default     = "us-central1-a"
}
