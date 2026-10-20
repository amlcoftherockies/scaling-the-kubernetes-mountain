data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

data "oci_containerengine_cluster_option" "all" {
  cluster_option_id = "all"
}

data "oci_containerengine_node_pool_option" "all" {
  node_pool_option_id = "all"
  compartment_id      = local.compartment_id
}

locals {
  k8s_version = var.kubernetes_version != "" ? var.kubernetes_version : element(
    data.oci_containerengine_cluster_option.all.kubernetes_versions,
    length(data.oci_containerengine_cluster_option.all.kubernetes_versions) - 1
  )

  # OKE node images are named like
  #   Oracle-Linux-8.10-2025.01.31-0-OKE-1.31.1-760          (x86_64)
  #   Oracle-Linux-8.10-aarch64-2025.01.31-0-OKE-1.31.1-760  (ARM)
  # Pick an x86_64 Oracle Linux 8 image built for this k8s version.
  image_regex = "^Oracle-Linux-8\\.[0-9]+-20[0-9]{2}\\..*-OKE-${trimprefix(local.k8s_version, "v")}-"
  node_images = [
    for s in data.oci_containerengine_node_pool_option.all.sources :
    s.image_id if length(regexall(local.image_regex, s.source_name)) > 0
    && length(regexall("GPU|aarch64", s.source_name)) == 0
  ]
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = local.compartment_id
  name               = local.name
  kubernetes_version = local.k8s_version
  vcn_id             = oci_core_vcn.this.id
  # ENHANCED, not BASIC: Oracle caps Basic clusters at 15 per region with no
  # way to raise it, which is fewer than a workshop needs. Enhanced clusters
  # have a raisable limit and cost ~$0.10/cluster-hour for the control plane.
  type = "ENHANCED_CLUSTER"

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  endpoint_config {
    subnet_id            = oci_core_subnet.api.id
    is_public_ip_enabled = true
  }

  options {
    # Services of type LoadBalancer are provisioned into this subnet.
    service_lb_subnet_ids = [oci_core_subnet.lb.id]
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}

resource "oci_containerengine_node_pool" "this" {
  compartment_id     = local.compartment_id
  cluster_id         = oci_containerengine_cluster.this.id
  name               = "${local.name}-pool"
  kubernetes_version = local.k8s_version
  # AMD EPYC (x86_64). Same CPU architecture as most laptops and most
  # images on Docker Hub, so nothing needs cross-building.
  node_shape = "VM.Standard.E5.Flex"

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gbs
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.node_images[0]
  }

  node_config_details {
    size = var.node_count

    # Spread nodes across availability domains; also lets OKE fall back to
    # another AD if one is temporarily out of capacity.
    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ads.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.nodes.id
      }
    }
  }

  initial_node_labels {
    key   = "workshop-owner"
    value = local.name
  }

  lifecycle {
    precondition {
      condition     = length(local.node_images) > 0
      error_message = "No x86_64 OKE node image found for Kubernetes ${local.k8s_version}. Set kubernetes_version to an older release."
    }
  }
}
