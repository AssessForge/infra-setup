terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# VCN principal
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "assessforge-vcn"
  dns_label      = "assessforge"
  freeform_tags  = var.freeform_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Internet Gateway (subnet pública)
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

# NAT Gateway (subnet privada — saída para internet dos nodes)
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-natgw"
  block_traffic  = false
  freeform_tags  = var.freeform_tags
}

# Service Gateway (acesso a serviços OCI sem sair pela internet)
resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-sgw"
  freeform_tags  = var.freeform_tags

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# Route table — subnet pública
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-rt-public"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# Route table — subnet privada
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-rt-private"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }
}

# NSG — Load Balancer
resource "oci_core_network_security_group" "lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-lb"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "lb_ingress_http" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_ingress_https" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_egress_workers" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = oci_core_network_security_group.workers.id
  destination_type          = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

# NSG — Worker nodes
resource "oci_core_network_security_group" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-workers"
  freeform_tags  = var.freeform_tags
}

# Ingress do LB para os workers — apenas NodePort range (30000-32767)
resource "oci_core_network_security_group_security_rule" "workers_ingress_from_lb" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

# Inter-node comunicação entre nodes (subnet privada)
resource "oci_core_network_security_group_security_rule" "workers_ingress_inter_node" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = var.private_subnet_cidr
  source_type               = "CIDR_BLOCK"
}

# Pod-to-pod cross-node (overlay CIDR 10.244.0.0/16)
resource "oci_core_network_security_group_security_rule" "workers_ingress_pod_cidr" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = "10.244.0.0/16"
  source_type               = "CIDR_BLOCK"
}


# Egress workers → tudo
resource "oci_core_network_security_group_security_rule" "workers_egress_all" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# NSG — Bastion
resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-bastion"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "bastion_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.bastion_allowed_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# Subnet pública — LB e Bastion
resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "assessforge-subnet-public"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  freeform_tags              = var.freeform_tags
}

# Subnet privada — worker nodes
resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "assessforge-subnet-private"
  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  freeform_tags              = var.freeform_tags
}

# NSG — API endpoint do cluster OKE (separado dos workers)
resource "oci_core_network_security_group" "api_endpoint" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-api-endpoint"
  freeform_tags  = var.freeform_tags
}

# Bastion → API endpoint (port 6443 apenas)
resource "oci_core_network_security_group_security_rule" "api_endpoint_ingress_bastion" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.bastion.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# --- Regras api_endpoint <-> workers (exigidas pela OKE para registro dos nodes) ---
# Referencia: https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfig.htm

# Workers precisam acessar o Kubernetes API (TCP 6443) para registrar kubelet e executar chamadas de cluster
resource "oci_core_network_security_group_security_rule" "api_endpoint_ingress_workers_kubeapi" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.workers.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# Canal dedicado OKE worker-to-control-plane (TCP 12250) — sem esta regra os nodes nunca concluem o registro
resource "oci_core_network_security_group_security_rule" "api_endpoint_ingress_workers_okeport" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.workers.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 12250
      max = 12250
    }
  }
}

# Path MTU Discovery dos workers ate o API endpoint (ICMP type 3 code 4) — evita blackhole de pacotes grandes
resource "oci_core_network_security_group_security_rule" "api_endpoint_ingress_workers_pmtu" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "INGRESS"
  protocol                  = "1"
  source                    = oci_core_network_security_group.workers.id
  source_type               = "NETWORK_SECURITY_GROUP"

  icmp_options {
    type = 3
    code = 4
  }
}

# Control plane precisa alcancar a kubelet dos workers (TCP 10250) para exec/logs/metrics
resource "oci_core_network_security_group_security_rule" "api_endpoint_egress_workers_kubelet" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = oci_core_network_security_group.workers.id
  destination_type          = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

# Path MTU Discovery do control plane para os workers (ICMP type 3 code 4)
resource "oci_core_network_security_group_security_rule" "api_endpoint_egress_workers_pmtu" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "EGRESS"
  protocol                  = "1"
  destination               = oci_core_network_security_group.workers.id
  destination_type          = "NETWORK_SECURITY_GROUP"

  icmp_options {
    type = 3
    code = 4
  }
}

# Control plane alcanca o servico OKE e demais OCI Services via Service Gateway (HTTPS 443)
resource "oci_core_network_security_group_security_rule" "api_endpoint_egress_oci_services" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = data.oci_core_services.all.services[0].cidr_block
  destination_type          = "SERVICE_CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# Control plane -> kubelet nos workers (TCP 10250) — obrigatorio para exec, logs e port-forward
resource "oci_core_network_security_group_security_rule" "workers_ingress_from_api_endpoint_kubelet" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.api_endpoint.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

# Path MTU Discovery do control plane para os workers (ICMP type 3 code 4)
resource "oci_core_network_security_group_security_rule" "workers_ingress_from_api_endpoint_pmtu" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "1"
  source                    = oci_core_network_security_group.api_endpoint.id
  source_type               = "NETWORK_SECURITY_GROUP"

  icmp_options {
    type = 3
    code = 4
  }
}

resource "oci_logging_log_group" "vcn_flow_logs" {
  compartment_id = var.compartment_ocid
  display_name   = "assessforge-vcn-flow-logs"
  freeform_tags  = var.freeform_tags
}

resource "oci_logging_log" "flow_log_public" {
  display_name  = "assessforge-flow-log-public"
  log_group_id  = oci_logging_log_group.vcn_flow_logs.id
  log_type      = "SERVICE"
  freeform_tags = var.freeform_tags

  configuration {
    source {
      category    = "all"
      resource    = oci_core_subnet.public.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_ocid
  }

  is_enabled         = true
  retention_duration = 90
}

resource "oci_logging_log" "flow_log_private" {
  display_name  = "assessforge-flow-log-private"
  log_group_id  = oci_logging_log_group.vcn_flow_logs.id
  log_type      = "SERVICE"
  freeform_tags = var.freeform_tags

  configuration {
    source {
      category    = "all"
      resource    = oci_core_subnet.private.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_ocid
  }

  is_enabled         = true
  retention_duration = 90
}
