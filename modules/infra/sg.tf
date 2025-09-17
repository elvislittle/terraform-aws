# SECURITY GROUPS OF INFRASTRUCTURE MODULE

# ALB Security Group

# Create a security group for the ALB - acts as firewall for load balancer
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg" # nginx-alb-sg, apache-alb-sg
  description = "Security group for ALB"
  vpc_id      = aws_vpc.this.id
}

# Allow internet traffic to ALB from anywhere (internet → ALB traffic flow)
resource "aws_vpc_security_group_ingress_rule" "internet_to_alb" {
  for_each          = var.allowed_ips           # Loop over allowed IPs (list of CIDR blocks) - allowed_ips is defined as a SET of strings to work with for_each
  security_group_id = aws_security_group.alb.id # Security group of ALB
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Allow HTTP traffic from internet to ALB"
}

# Allow ALB to send traffic to ECS containers (ALB → ECS traffic flow)
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_egress" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  description                  = "Allow HTTP traffic from ALB to ECS tasks"
}

# ECS Tasks Security Group

# Create a security group for the ECS tasks - acts as firewall for app containers
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_name}-ecs-sg" # nginx-ecs-sg, apache-ecs-sg
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.this.id
}

# Allow ALB to send requests to ECS containers (ALB → ECS traffic flow)
resource "aws_vpc_security_group_ingress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.ecs_tasks.id # Security group of ECS tasks (containers)
  referenced_security_group_id = aws_security_group.alb.id       # Reference security group of ALB to allow traffic from it
  from_port                    = var.app_port                    # Start of port range (80)
  to_port                      = var.app_port                    # End of port range (80) = SINGLE PORT
  ip_protocol                  = "tcp"
  description                  = "Allow HTTP traffic from ALB to ECS tasks"
}

# Allow ECS containers to access internet (for ECR pulls, API calls, etc.)
resource "aws_vpc_security_group_egress_rule" "ecs_to_anywhere" {
  security_group_id = aws_security_group.ecs_tasks.id # Security group of ECS tasks (containers)
  cidr_ipv4         = "0.0.0.0/0"                     # Destination for all IPv4 traffic - anywhere
  ip_protocol       = "-1"                            # All protocols (TCP, UDP, ICMP, etc.)
  description       = "Allow all outbound traffic from ECS tasks"
}