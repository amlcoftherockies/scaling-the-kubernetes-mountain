terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# --- Networking ---

resource "google_compute_network" "k8s_vpc" {
  name                    = "k8s-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "k8s-subnet"
  ip_cidr_range = "10.240.0.0/24"
  network       = google_compute_network.k8s_vpc.id
  region        = var.gcp_region
}

# --- GKE Cluster ---

resource "google_container_cluster" "primary" {
  name     = "ckad-cluster"
  location = var.gcp_zone

  # We delete the default node pool and create our own custom node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.k8s_vpc.id
  subnetwork = google_compute_subnetwork.k8s_subnet.id

  # Required to allow terraform destroy to clean up the cluster without human intervention
  deletion_protection = false
}

# --- GKE Node Pool ---

resource "google_container_node_pool" "primary_nodes" {
  name       = "ckad-node-pool"
  location   = var.gcp_zone
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 30
    disk_type    = "pd-standard"

    # Use Spot instances to reduce costs by 60-80% (perfect for workshops)
    spot = true

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
