# VARIABLES FOR APP MODULE

# Name of the ECR repository to be created
variable "ecr_repository_name" {
  description = "The name of the ECR repository"
  type        = string
}

# Path to the application code relative to the module directory
variable "app_path" {
  description = "Path to the application code relative to the module directory"
  type        = string
}

# Version tag for the application Docker image
variable "app_version" {
  description = "Version tag for the application Docker image"
  type        = string
}

# Name of the application (used in ECS task definition)
variable "app_name" {
  description = "Name of the application"
  type        = string
}

# Port on which the application listens
variable "app_port" {
  description = "Port on which the application listens"
  type        = number
  default     = 80
}

# ARN of the IAM role that the ECS tasks will use for execution
variable "app_execution_role_arn" {
  description = "ARN of the IAM role that the ECS tasks will use for execution"
  type        = string
}

# Visibility of the ECS service (public or private)
variable "is_public" {
  description = "Whether the application should be publicly accessible"
  type        = bool
}

# List of subnet IDs where the ECS tasks will be deployed
variable "subnet_ids" {
  description = "List of subnet IDs where the ECS tasks will be deployed"
  type        = list(string)
}

# Security group ID to associate with the ECS tasks
variable "app_security_group_id" {
  description = "Security group ID to associate with the ECS tasks"
  type        = string
}

# ARN of the target group to associate with the ECS service
variable "alb_target_group_arn" {
  description = "ARN of the target group to associate with the ECS service"
  type        = string
}