terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# --- Topico ONS para alertas de billing ---

resource "oci_ons_notification_topic" "billing" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-billing-alerts"
  description    = "Alertas quando qualquer custo de billing for maior que zero"
  freeform_tags  = var.freeform_tags
}

# --- Uma subscription por email na lista ---

resource "oci_ons_subscription" "billing_email" {
  for_each = toset(var.notification_emails)

  compartment_id = var.compartment_ocid
  topic_id       = oci_ons_notification_topic.billing.id
  protocol       = "EMAIL"
  endpoint       = each.value
  freeform_tags  = var.freeform_tags
}

# --- Alarme de billing — dispara quando qualquer custo > 0 ---

resource "oci_monitoring_alarm" "billing_cost" {
  compartment_id        = var.compartment_ocid
  display_name          = "assessforge-billing-cost-alarm"
  is_enabled            = true
  metric_compartment_id = var.tenancy_ocid
  namespace             = "oci_billing"
  query                 = "CostByService[1d].sum() > 0"
  severity              = "CRITICAL"
  destinations          = [oci_ons_notification_topic.billing.id]
  body                  = "ALERTA: Custo de billing OCI detectado acima de zero. Verifique o Cost Analysis no OCI Console para identificar o recurso."
  message_format        = "ONS_OPTIMIZED"
  pending_duration      = "PT1H"

  repeat_notification_duration = "P1D"

  freeform_tags = var.freeform_tags
}
