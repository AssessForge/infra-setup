output "alarm_id" {
  description = "OCID do alarme de billing"
  value       = oci_monitoring_alarm.billing_cost.id
}

output "topic_id" {
  description = "OCID do topico ONS de billing"
  value       = oci_ons_notification_topic.billing.id
}
