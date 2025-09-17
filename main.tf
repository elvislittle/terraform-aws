# MAIN TERRAFORM CONFIGURATION

# Define multiple applications with their configurations
locals {
  apps = {
    nginx = {
      ecr_repository_name = "nginx"
      app_path            = "nginx"
      app_version         = "v1.0.2"
      app_name            = "nginx"
      app_port            = 80
      is_public           = true
    }
    apache = {
      ecr_repository_name = "apache"
      app_path            = "apache"
      app_version         = "v1.0.1"
      app_name            = "apache"
      app_port            = 80
      is_public           = true
    }
  }
}

# Create infrastructure for each app (separate ALB per app)
module "infra" {
  for_each      = local.apps
  source        = "./modules/infra"
  vpc_cidr      = "10.0.0.0/16"
  subnet_number = 2
  allowed_ips   = ["0.0.0.0/0"]
  app_name      = each.value.app_name
  app_port      = each.value.app_port
  path_pattern  = "/*" # Add this line
}

# Create each app with its own infrastructure
module "apps" {
  for_each               = local.apps
  source                 = "./modules/app"
  ecr_repository_name    = each.value.ecr_repository_name
  app_path               = each.value.app_path
  app_version            = each.value.app_version
  app_name               = each.value.app_name
  app_port               = each.value.app_port
  is_public              = each.value.is_public
  app_execution_role_arn = module.infra[each.key].app_execution_role_arn
  subnet_ids             = module.infra[each.key].aws_subnet_ids
  app_security_group_id  = module.infra[each.key].app_security_group_id
  alb_target_group_arn   = module.infra[each.key].alb_target_group_arn
}