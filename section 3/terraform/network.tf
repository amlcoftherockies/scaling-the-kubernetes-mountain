# Network layout
#   10.0.0.0/28   api   (public)  - Kubernetes API endpoint, reachable by kubectl
#   10.0.10.0/24  nodes (private) - workers, internet egress via NAT, no public IPs
#   10.0.20.0/24  lb    (public)  - where `type: LoadBalancer` Services land

locals {
  vcn_cidr   = "10.0.0.0/16"
  api_cidr   = "10.0.0.0/28"
  nodes_cidr = "10.0.10.0/24"
  lb_cidr    = "10.0.20.0/24"
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "this" {
  compartment_id = local.compartment_id
  display_name   = "${local.name}-vcn"
  cidr_blocks    = [local.vcn_cidr]
  dns_label      = substr(replace(lower(local.name), "/[^a-z0-9]/", ""), 0, 15)
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-igw"
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-nat"
}

resource "oci_core_service_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-sgw"
  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-public-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-private-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.this.id
  }
  # Nodes reach OKE and OCIR (container registry) over the service gateway.
  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

# -- security lists -----------------------------------------------------------

resource "oci_core_security_list" "api" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-api-sl"

  ingress_security_rules {
    description = "kubectl"
    protocol    = "6"
    source      = var.api_allowed_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  ingress_security_rules {
    description = "workers to API"
    protocol    = "6"
    source      = local.nodes_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  ingress_security_rules {
    description = "workers to control plane"
    protocol    = "6"
    source      = local.nodes_cidr
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  ingress_security_rules {
    description = "path MTU discovery"
    protocol    = "1"
    source      = local.nodes_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "nodes" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-nodes-sl"

  ingress_security_rules {
    description = "node to node / pod to pod"
    protocol    = "all"
    source      = local.nodes_cidr
  }
  ingress_security_rules {
    description = "control plane to workers"
    protocol    = "6"
    source      = local.api_cidr
  }
  ingress_security_rules {
    description = "load balancers to NodePorts and kube-proxy health checks"
    protocol    = "6"
    source      = local.lb_cidr
  }
  ingress_security_rules {
    description = "path MTU discovery"
    protocol    = "1"
    source      = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "lb" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-lb-sl"

  # Ports your LoadBalancer Services may listen on. Add more if you need them.
  dynamic "ingress_security_rules" {
    for_each = [80, 443]
    content {
      description = "public traffic to load balancers"
      protocol    = "6"
      source      = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }

  egress_security_rules {
    description = "load balancers to worker NodePorts"
    protocol    = "6"
    destination = local.nodes_cidr
  }
}

# -- subnets ------------------------------------------------------------------

resource "oci_core_subnet" "api" {
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.this.id
  display_name      = "${local.name}-api"
  cidr_block        = local.api_cidr
  dns_label         = "api"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.api.id]
}

resource "oci_core_subnet" "nodes" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${local.name}-nodes"
  cidr_block                 = local.nodes_cidr
  dns_label                  = "nodes"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.nodes.id]
}

resource "oci_core_subnet" "lb" {
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.this.id
  display_name      = "${local.name}-lb"
  cidr_block        = local.lb_cidr
  dns_label         = "lb"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.lb.id]
}
