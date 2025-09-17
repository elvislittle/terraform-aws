# MAIN TERRAFORM CONFIGURATION

# Call infrastructure module - creates VPC, subnets, ALB, security groups, and IAM roles
module "infra" {
  source        = "./modules/infra"
  vpc_cidr      = "10.0.0.0/16" # Network range for VPC (65,536 IP addresses)
  subnet_number = 2             # Create 2 subnets across different AZs
  allowed_ips   = ["0.0.0.0/0"] # Allow internet access from anywhere (is set as a set of CIDR blocks to iterate with for_each when creating SG ingress rules)
  app_port      = "80"          # Port where application listens
  path_pattern  = "/*"          # Path pattern for listener rule (all requests)
}

# Call app module - creates ECS cluster, ECR repo, builds/pushes Docker image, runs containers
module "app" {
  source                 = "./modules/app"
  ecr_repository_name    = "ui"                                # Name for Docker image repository
  app_path               = "ui"                                # Folder containing Dockerfile
  app_version            = "v1.0.2"                            # Version tag for Docker image
  app_name               = "ui"                                # Name for ECS service and containers
  app_port               = "80"                                # Port application listens on
  app_execution_role_arn = module.infra.app_execution_role_arn # IAM role from infra module
  is_public              = true                                # Give containers public IP
  subnet_ids             = module.infra.aws_subnet_ids         # Subnets from infra module
  app_security_group_id  = module.infra.app_security_group_id  # Security group for ECS Tasks (app containers) from infra module
  alb_target_group_arn   = module.infra.alb_target_group_arn   # Target group from infra module
}