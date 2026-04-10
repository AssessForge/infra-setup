# Versão mais recente estável do Kubernetes no OKE
data "oci_containerengine_cluster_option" "k8s_versions" {
  cluster_option_id = "all"
}

locals {
  # Selects the latest available version using lexicographic sort.
  # Safe while all supported versions share the same major.minor prefix length
  # (e.g. v1.28–v1.31). If OCI ever offers v1.9.x alongside v1.10.x+ this
  # would break — set var.kubernetes_version to pin an explicit version instead.
  k8s_version = var.kubernetes_version != "" ? var.kubernetes_version : reverse(
    sort(
      [for v in data.oci_containerengine_cluster_option.k8s_versions.kubernetes_versions : v]
    )
  )[0]
}

# TODO: OKE audit log — service name desconhecido no Terraform.
# Habilitar manualmente pelo Console OCI: Logging > Service Logs > Container Engine for Kubernetes
# resource "oci_logging_log_group" "oke_audit" {
#   compartment_id = var.compartment_ocid
#   display_name   = "assessforge-oke-audit-logs"
#   freeform_tags  = var.freeform_tags
# }

# Cluster OKE BASIC
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = local.k8s_version
  name               = var.cluster_name
  vcn_id             = var.vcn_id
  type               = "BASIC_CLUSTER"
  freeform_tags      = var.freeform_tags

  endpoint_config {
    is_public_ip_enabled = false
    nsg_ids              = [var.api_endpoint_nsg_id]
    subnet_id            = var.private_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.public_subnet_id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# resource "oci_logging_log" "oke_audit" {
#   display_name  = "assessforge-oke-audit"
#   log_group_id  = oci_logging_log_group.oke_audit.id
#   log_type      = "SERVICE"
#   freeform_tags = var.freeform_tags
#
#   configuration {
#     source {
#       category    = "all"
#       resource    = oci_containerengine_cluster.main.id
#       service     = "???"
#       source_type = "OCISERVICE"
#     }
#     compartment_id = var.compartment_ocid
#   }
#
#   is_enabled         = true
#   retention_duration = 90
#
#   depends_on = [oci_containerengine_cluster.main]
# }

# Imagens OKE-validas para o cluster
data "oci_containerengine_node_pool_option" "images" {
  node_pool_option_id = oci_containerengine_cluster.main.id
  compartment_id      = var.compartment_ocid
}

locals {
  # Filtra imagens aarch64 (ARM) para shape A1
  arm_images = [
    for s in data.oci_containerengine_node_pool_option.images.sources :
    s if length(regexall("aarch64", s.source_name)) > 0
  ]
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# Node pool — 2 nodes A1
resource "oci_containerengine_node_pool" "main" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = local.k8s_version
  name               = "${var.cluster_name}-np"
  freeform_tags      = var.freeform_tags

  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }

  node_source_details {
    image_id                = local.arm_images[0].image_id
    source_type             = "IMAGE"
    boot_volume_size_in_gbs = 50
  }

  node_config_details {
    size = 2

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = var.private_subnet_id
    }

    nsg_ids = [var.workers_nsg_id]
  }

  lifecycle {
    prevent_destroy = true
  }
}

# OCI Bastion Service — target_subnet_id aponta para a subnet PRIVADA onde estão os workers
resource "oci_bastion_bastion" "main" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = var.private_subnet_id
  name                         = "assessforge-bastion"
  client_cidr_block_allow_list = [var.bastion_allowed_cidr]
  freeform_tags                = var.freeform_tags
}

# Geração do kubeconfig após o cluster estar pronto
resource "null_resource" "kubeconfig" {
  triggers = {
    cluster_id = oci_containerengine_cluster.main.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      oci ce cluster create-kubeconfig \
        --cluster-id ${oci_containerengine_cluster.main.id} \
        --file ~/.kube/config-assessforge \
        --auth api_key \
        --overwrite
    EOT
  }

  depends_on = [oci_containerengine_node_pool.main]
}
