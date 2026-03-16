# Versão mais recente estável do Kubernetes no OKE
data "oci_containerengine_cluster_option" "k8s_versions" {
  cluster_option_id = "all"
}

locals {
  # Pega a última versão disponível (ex: v1.31.1)
  k8s_version = reverse(
    sort(
      [for v in data.oci_containerengine_cluster_option.k8s_versions.kubernetes_versions : v]
    )
  )[0]
}

# Log group para audit logs do OKE
resource "oci_logging_log_group" "oke_audit" {
  compartment_id = var.compartment_ocid
  display_name   = "assessforge-oke-audit-logs"
  freeform_tags  = var.freeform_tags
}

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
    nsg_ids              = [var.workers_nsg_id]
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

resource "oci_logging_log" "oke_audit" {
  display_name  = "assessforge-oke-audit"
  log_group_id  = oci_logging_log_group.oke_audit.id
  log_type      = "SERVICE"
  freeform_tags = var.freeform_tags

  configuration {
    source {
      category    = "kube-apiserver-audit"
      resource    = oci_containerengine_cluster.main.id
      service     = "oke"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_ocid
  }

  is_enabled         = true
  retention_duration = 30

  depends_on = [oci_containerengine_cluster.main]
}

# Image Oracle Linux mais recente para A1
data "oci_core_images" "oracle_linux_a1" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
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
    image_id                = data.oci_core_images.oracle_linux_a1.images[0].id
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
}

# OCI Bastion Service — reside na subnet PÚBLICA para ser acessível da internet
resource "oci_bastion_bastion" "main" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = var.public_subnet_id
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
