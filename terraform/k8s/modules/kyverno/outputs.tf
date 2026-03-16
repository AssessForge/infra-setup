output "release_status" {
  description = "Status do Helm release do Kyverno"
  value       = helm_release.kyverno.status
}
