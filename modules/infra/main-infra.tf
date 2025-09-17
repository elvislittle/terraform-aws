# INFRASTRUCTURE MODULE

# Create a VPC - isolated network environment for all AWS resources
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "tf-ecs-vpc"
  }
}

# Create an internet gateway - provides internet access to/from VPC
resource "aws_internet_gateway" "this" {
  tags = {
    Name = "tf-ecs-igw"
  }
}

# Attach the internet gateway to the VPC - connects VPC to internet
resource "aws_internet_gateway_attachment" "this" {
  vpc_id              = aws_vpc.this.id
  internet_gateway_id = aws_internet_gateway.this.id
}

# Create a route table - defines where network traffic should go
resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "tf-ecs-rt"
  }
}

# Create a default route to the internet gateway - sends all internet traffic (0.0.0.0/0) through IGW
resource "aws_route" "this" {
  route_table_id         = aws_route_table.this.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Fetch available AWS availability zones - gets list of AZs in current region
data "aws_availability_zones" "available" {
  state = "available"
}

# Define local variables to ease calculations of availability zones
locals {
  azs = data.aws_availability_zones.available.names
}

# Create subnets in the VPC - network segments where resources are placed (for_each creates multiple subnets)
resource "aws_subnet" "this" {
  for_each = { for i in range(var.subnet_number) : "public-${i}" => i }
  vpc_id   = aws_vpc.this.id
  #   cidr_block  = "10.0.${each.value}.0/24"
  #   cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value)
  cidr_block = cidrsubnet(aws_vpc.this.cidr_block, 8, each.value) # Auto-calculates subnet CIDR (10.0.0.0/24, 10.0.1.0/24, etc.)
  #   availability_zone = data.aws_availability_zones.available.names[each.value]
  availability_zone = local.azs[each.value % length(local.azs)] # Distributes subnets across different AZs for high availability. Modulo operator (%) wraps around if more subnets than AZs
  tags = {
    Name = "tf-ecs-${each.key}"
  }
}

# Associate the route table with the subnets - connects subnets to routing rules (gives subnets internet access)
resource "aws_route_table_association" "this" {
  for_each  = aws_subnet.this # Loop over all created subnets
  subnet_id = each.value.id   # the key is "public-0", "public-1", etc., the value is the subnet object
  # the same as
  #   subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this.id # same for all subnets
}

# Create a load balancer - distributes incoming internet traffic across ECS containers
resource "aws_lb" "this" {
  name               = "tf-ecs-lb"
  internal           = false         # Internet-facing (not internal)
  load_balancer_type = "application" # Layer 7 HTTP/HTTPS load balancer
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.this : subnet.id] # Deployed across multiple subnets for high availability
}

# Create a listener for the load balancer - defines what port ALB listens on and what to do with requests
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80" # Listen on port 80 for HTTP traffic
  protocol          = "HTTP"
  # default_action {
  #   type = "fixed-response"  # Default response when no ECS tasks are available
  #   fixed_response {
  #     content_type = "text/plain"
  #     message_body = "ALB is working, but ECS tasks are not there yet"
  #     status_code  = "503"
  #   }
  # }
  default_action {                                  # Default action when no listener rules match
    type             = "forward"                    # Forward traffic to target group
    target_group_arn = aws_lb_target_group.this.arn # Send to ECS containers
  }
}

# Here OPTIONAL - create a listener RULE - routes requests based on conditions
resource "aws_lb_listener_rule" "this" {
  listener_arn = aws_lb_listener.this.arn
  priority     = 100

  condition {
    path_pattern {
      values = [var.path_pattern] # Match all paths (/*
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

}

# Create a target group - shared registry where ECS registers healthy containers and ALB finds targets to route traffic to
resource "aws_lb_target_group" "this" {
  name        = "tf-alb-tg"
  port        = var.app_port # Port where containers listen
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip" # Track containers by IP address (required for Fargate)

  health_check {
    enabled             = true
    healthy_threshold   = 2     # 2 successful checks = healthy
    unhealthy_threshold = 2     # 2 failed checks = unhealthy
    timeout             = 5     # Wait 5 seconds for response
    interval            = 30    # Check every 30 seconds
    path                = "/"   # Check this URL path
    matcher             = "200" # Expect HTTP 200 response
  }
}

# IAM role for ECS task execution - to give ECS permission (e.g. to pull images from ECR and write logs) AFTER attaching the corresponding IAM policy to the role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com" # Only ECS service can assume this role
        }
      }
    ]
  })
}

# IAM role policy attachment - attaches AWS managed policy that allows ECR pulls and CloudWatch logs
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}