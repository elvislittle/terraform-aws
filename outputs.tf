# Output ALB URLs for each app
output "app_urls" {
  description = "URLs for accessing each application"
  value = {
    for app_name, app_config in local.apps :
    app_name => "http://${module.infra[app_name].alb_dns_name}"
  }
}