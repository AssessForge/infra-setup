# Habilitar Cloud Guard no tenancy
resource "oci_cloud_guard_cloud_guard_configuration" "main" {
  compartment_id   = var.tenancy_ocid
  reporting_region = var.region
  status           = "ENABLED"
}

# Data source: Oracle Managed Detector Recipe
# depends_on garante leitura apos Cloud Guard ser habilitado (nao durante plan)
data "oci_cloud_guard_detector_recipes" "oracle_managed" {
  compartment_id = var.tenancy_ocid

  filter {
    name   = "display_name"
    values = ["OCI Configuration Detector Recipe"]
    regex  = false
  }

  depends_on = [oci_cloud_guard_cloud_guard_configuration.main]
}

# Detector Recipe clonado do Oracle Managed
resource "oci_cloud_guard_detector_recipe" "assessforge" {
  compartment_id            = var.compartment_ocid
  display_name              = "assessforge-detector-recipe"
  source_detector_recipe_id = data.oci_cloud_guard_detector_recipes.oracle_managed.detector_recipe_collection[0].items[0].id
  freeform_tags             = var.freeform_tags

  depends_on = [oci_cloud_guard_cloud_guard_configuration.main]
}

# Data source: Oracle Managed Responder Recipe
# depends_on garante leitura apos Cloud Guard ser habilitado (nao durante plan)
data "oci_cloud_guard_responder_recipes" "oracle_managed" {
  compartment_id = var.tenancy_ocid

  filter {
    name   = "display_name"
    values = ["OCI Notification Responder Recipe"]
    regex  = false
  }

  depends_on = [oci_cloud_guard_cloud_guard_configuration.main]
}

# Responder Recipe clonado
resource "oci_cloud_guard_responder_recipe" "assessforge" {
  compartment_id             = var.compartment_ocid
  display_name               = "assessforge-responder-recipe"
  source_responder_recipe_id = data.oci_cloud_guard_responder_recipes.oracle_managed.responder_recipe_collection[0].items[0].id
  freeform_tags              = var.freeform_tags

  depends_on = [oci_cloud_guard_cloud_guard_configuration.main]
}

# Target apontando para o compartment do projeto
resource "oci_cloud_guard_target" "assessforge" {
  compartment_id       = var.compartment_ocid
  display_name         = "assessforge-cloud-guard-target"
  target_resource_id   = var.compartment_ocid
  target_resource_type = "COMPARTMENT"
  freeform_tags        = var.freeform_tags

  target_detector_recipes {
    detector_recipe_id = oci_cloud_guard_detector_recipe.assessforge.id
  }

  target_responder_recipes {
    responder_recipe_id = oci_cloud_guard_responder_recipe.assessforge.id
  }

  depends_on = [
    oci_cloud_guard_detector_recipe.assessforge,
    oci_cloud_guard_responder_recipe.assessforge,
  ]
}

# Tópico ONS para alertas do Cloud Guard
resource "oci_ons_notification_topic" "cloud_guard" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-cloud-guard-alerts"
  description    = "Alertas de problemas detectados pelo Cloud Guard"
  freeform_tags  = var.freeform_tags
}

# Subscription por email (condicional — só cria se notification_email estiver definido)
resource "oci_ons_subscription" "cloud_guard_email" {
  count = var.notification_email != "" ? 1 : 0

  compartment_id = var.compartment_ocid
  topic_id       = oci_ons_notification_topic.cloud_guard.id
  protocol       = "EMAIL"
  endpoint       = var.notification_email
  freeform_tags  = var.freeform_tags
}

# OCI Events rule — encaminha eventos do Cloud Guard para o tópico ONS
resource "oci_events_rule" "cloud_guard_alerts" {
  compartment_id = var.compartment_ocid
  display_name   = "assessforge-cloud-guard-events"
  is_enabled     = true
  freeform_tags  = var.freeform_tags

  condition = jsonencode({
    eventType = [
      "com.oraclecloud.cloudguard.problemdetected",
      "com.oraclecloud.cloudguard.problemthresholdreached",
    ]
  })

  actions {
    actions {
      action_type = "ONS"
      is_enabled  = true
      topic_id    = oci_ons_notification_topic.cloud_guard.id
    }
  }

  depends_on = [oci_cloud_guard_target.assessforge]
}
