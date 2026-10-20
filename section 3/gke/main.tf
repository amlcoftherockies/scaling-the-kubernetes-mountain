# -- APIs ---------------------------------------------------------------------

resource "google_project_service" "apis" {
  for_each           = toset(["compute.googleapis.com", "container.googleapis.com", "billingbudgets.googleapis.com"])
  service            = each.value
  disable_on_destroy = false
}

# -- network: private nodes, NAT for image pulls ------------------------------

resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "nodes" {
  name          = "${var.cluster_name}-nodes"
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/20"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/14"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
  private_ip_google_access = true
}

resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

# Nodes have no public IPs; NAT lets them pull from Docker Hub etc.
resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# -- least-privilege node identity --------------------------------------------
# The default compute service account has Editor on the whole project. Nodes
# get a dedicated account that can only write logs/metrics and pull images.

resource "google_service_account" "nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE nodes for ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# -- cluster -------------------------------------------------------------------

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.nodes.id

  # We manage our own node pool below.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 enforces NetworkPolicy (participants practice it; labctl
  # uses it to fence namespaces apart).
  datapath_provider = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.api_allowed_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "allowed"
      }
    }
  }

  # Workload Identity: pods get NO Google credentials unless explicitly bound,
  # and the node metadata server is hidden from them.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # No basic auth / client certs: only Google IAM or Kubernetes tokens.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "default" {
  name     = "default"
  cluster  = google_container_cluster.this.id
  location = var.zone

  initial_node_count = var.min_nodes
  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot = true
    }
    labels = { workshop = var.cluster_name }
  }
}

resource "google_container_node_pool" "gvisor" {
  count    = var.enable_gvisor_pool ? 1 : 0
  name     = "gvisor"
  cluster  = google_container_cluster.this.id
  location = var.zone

  node_count = 1

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = 50
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    sandbox_config {
      type = "GVISOR"
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

# -- optional budget alert -----------------------------------------------------

data "google_project" "this" {}

resource "google_billing_budget" "this" {
  count           = var.budget_amount_usd > 0 && var.billing_account_id != "" ? 1 : 0
  billing_account = var.billing_account_id
  display_name    = "${var.cluster_name} budget"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.9 }
  threshold_rules { threshold_percent = 1.0 }
}
