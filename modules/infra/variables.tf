# VARIABLES FOR INFRA MODULE

# Define the CIDR block variable for the VPC
variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

# Define the number of subnets variable
variable "subnet_number" {
  description = "Number of subnets to create"
  type        = number
}

# Define the allowed IPs variable
variable "allowed_ips" {
  description = "List of allowed IPs for security group"
  type        = set(string)
}

# Define the app port variable
variable "app_port" {
  description = "Port on which the application listens"
  type        = number
}

# Define the path pattern variable for listener rule
variable "path_pattern" {
  description = "Path pattern for listener rule"
  type        = string
}

# MULTIPLE APPS SUPPORT

# Define the app name variable
variable "app_name" {
  description = "Name of the application for resource naming"
  type        = string
}