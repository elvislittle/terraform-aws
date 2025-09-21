# MAIN TERRAFORM CONFIGURATION

# Explanation of workspaces in CLI:
# - terraform workspace list          # Show all workspaces
# - terraform workspace new dev       # Create new workspace
# - terraform workspace select dev    # Switch to workspace
# - terraform workspace show          # Show current workspace
# Each workspace has separate state files for isolated environments

# WARNING: Current configuration does NOT support multiple workspaces due to hardcoded resource names
# Creating new workspaces (dev/prod) will cause AWS resource naming conflicts because:
# - ALB names: "nginx-alb", "apache-alb" (same across workspaces)
# - ECR repos: "nginx", "apache" (same across workspaces) 
# - ECS cluster: "tf-ecs-cluster" (same across workspaces)
# 
# TO ENABLE WORKSPACE SUPPORT IN FUTURE:
# 1. Add workspace suffix to app names: app_name = "nginx-${terraform.workspace}"
# 2. Add workspace suffix to ECR repos: ecr_repository_name = "nginx-${terraform.workspace}"
# 3. Update ECS cluster name in modules/app/main-app.tf: name = "tf-ecs-cluster-${terraform.workspace}"
# 4. This will create unique names like: nginx-dev-alb, apache-prod, tf-ecs-cluster-dev
# 
# CURRENT STATUS: Only use 'default' workspace to avoid conflicts

# Get secret from Secrets Manager
data "aws_secretsmanager_secret" "OPEN_AI_API_KEY" {
  name = "OPEN_AI_API_KEY"
}

# Define multiple applications with their configurations
locals {
  apps = {
    # nginx = {
    #   ecr_repository_name = "nginx"
    #   app_path            = "nginx"
    #   app_version         = "v1.0.2"
    #   app_name            = "nginx"
    #   app_port            = 80
    #   is_public           = true
    # }
    # apache = {
    #   ecr_repository_name = "apache"
    #   app_path            = "apache"
    #   app_version         = "v1.0.1"
    #   app_name            = "apache"
    #   app_port            = 80
    #   is_public           = true
    # }
    # nginx = {
    #   ecr_repository_name = "nginx"
    #   app_path            = "nginx"
    #   app_version         = "v1.0.0"
    #   app_name            = "nginx"
    #   app_port            = 80
    #   is_public           = true
    #   path_pattern        = "/*"
    #   healthcheck_path    = "/"
    # }
    ui = {
      ecr_repository_name = "ui"
      app_path            = "ui"
      app_version         = "v1.0.0"
      app_name            = "ui"
      app_port            = 80
      is_public           = true
      path_pattern        = "/*"
      healthcheck_path    = "/"
      envars              = [{}]
      secrets             = [{}]
      lb_priority         = 20
    }
    api = {
      ecr_repository_name = "api"
      app_path            = "api"
      app_version         = "v1.0.13"
      app_name            = "api"
      app_port            = 5000
      is_public           = true
      path_pattern        = "/api/*"
      healthcheck_path    = "/api/healthcheck"
      envars              = [{}]
      secrets             = [{ name = "OPEN_AI_API_KEY", valueFrom = data.aws_secretsmanager_secret.OPEN_AI_API_KEY.arn }]
      lb_priority         = 10
    }
  }

  # Environment-specific configurations
  env_config = {
    default = { cidr = "10.0.0.0/16", num_subnets = 3, allowed_ips = ["0.0.0.0/0"] }
    dev     = { cidr = "10.1.0.0/16", num_subnets = 3, allowed_ips = ["127.0.0.1/32"] }
    prod    = { cidr = "10.2.0.0/16", num_subnets = 3, allowed_ips = ["0.0.0.0/0"] }
  }
}

# Create infrastructure for each app (separate ALB per app) - multi-environment
module "infra" {
  # for_each         = local.apps
  source        = "./modules/infra"
  vpc_cidr      = local.env_config[terraform.workspace].cidr
  subnet_number = local.env_config[terraform.workspace].num_subnets
  allowed_ips   = local.env_config[terraform.workspace].allowed_ips
  # app_name      = each.value.app_name
  # app_port      = each.value.app_port
}

# Create Dockerfile for the ui app
resource "local_file" "dockerfile" {
  content = templatefile("modules/app/apps/templates/ui.tftpl", {
    build_args = {
      backend_url = module.infra.alb_dns_name
    }
  })
  filename = "modules/app/apps/ui/Dockerfile"
}

# Create each app with its own infrastructure
module "app" {
  # depends_on             = [local_file.dockerfile]
  for_each               = local.apps
  source                 = "./modules/app"
  ecr_repository_name    = each.value.ecr_repository_name
  app_path               = each.value.app_path
  app_version            = each.value.app_version
  app_name               = each.value.app_name
  app_port               = each.value.app_port
  is_public              = each.value.is_public
  envars                 = each.value.envars
  secrets                = each.value.secrets
  app_execution_role_arn = module.infra.app_execution_role_arn
  subnet_ids             = module.infra.aws_subnet_ids
  app_security_group_id  = module.infra.app_security_group_id
  healthcheck_path       = each.value.healthcheck_path
  path_pattern           = each.value.path_pattern
  lb_priority            = each.value.lb_priority
  cluster_arn            = module.infra.cluster_arn
  vpc_id                 = module.infra.vpc_id
  alb_listener_arn       = module.infra.alb_listener_arn
}

# # A Simple example resource
# resource "aws_vpc" "this" {
#   cidr_block = "10.0.0.0/16"
# }