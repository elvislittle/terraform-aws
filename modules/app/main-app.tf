# APP MODULE

# Create local values for ECR token and URL - reusable variables for Docker operations
locals {
  ecr_token = data.aws_ecr_authorization_token.this  # Temporary auth token for ECR login - used by local-exec provisioner to login to ECR
  ecr_url   = aws_ecr_repository.this.repository_url # URL of the ECR repository - used by Docker build and push commands
}

# Create a ECR repository - private Docker registry to store your app images
resource "aws_ecr_repository" "this" {
  name         = var.ecr_repository_name
  force_delete = true # Allow deletion even if images in the repo exist
}

# Get ECR authorization token - temporary password to access ECR (works for ALL ECR repos IN REGION)
data "aws_ecr_authorization_token" "this" {} # the token is an OBJECT with user_name and password attributes

# Login to ECR - authenticate Docker with ECR so we can push images via local-exec provisioner, using token from data block
resource "terraform_data" "login" {
  provisioner "local-exec" {
    command = <<-EOF
    
    docker logout ${local.ecr_url} || true
    security delete-internet-password -s ${local.ecr_url} || true

    docker login ${local.ecr_url} \
    --username  ${local.ecr_token.user_name} \
    --password  ${local.ecr_token.password}
    EOF
  }
}

# Build a Docker image for the application - creates container image from your app code
resource "terraform_data" "build" {
  depends_on = [terraform_data.login] # Ensure we login to ECR before building the image
  triggers_replace = [
    var.app_version # Triggers rebuild when version changes
  ]
  provisioner "local-exec" {
    # Build the Docker image with name = ECR URL and tag = latest (implicit because no tag specified)
    command = "docker build --platform linux/amd64 -t ${local.ecr_url} ${path.module}/apps/${var.app_path}" # the general format is "docker build -t <image_name:tag> <path_to_dockerfile>"
  }
}

# Tag and push the Docker image - creates version tags and uploads to ECR
resource "terraform_data" "push" {
  triggers_replace = [
    var.app_version # Triggers re-push when version changes
  ]
  depends_on = [terraform_data.login, terraform_data.build] # Ensure we login to ECR and build the image before pushing
  # We use provisioner to: 1) tag the image with version and latest, 2) push both tags to ECR
  provisioner "local-exec" {
    command = <<-EOF
    docker image tag ${local.ecr_url} ${local.ecr_url}:${var.app_version}
    docker image tag ${local.ecr_url} ${local.ecr_url}:latest
    docker image push ${local.ecr_url}:${var.app_version}
    docker image push ${local.ecr_url}:latest
    EOF
  }
}

# Create CloudWatch log group for container logs
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.app_name}-task" # Log group name based on app name
  retention_in_days = 7
}

# Create an ECS Task Definition - blueprint that defines how containers should run
resource "aws_ecs_task_definition" "this" {
  depends_on               = [aws_cloudwatch_log_group.this]
  family                   = "${var.app_name}-task"     # Fmaily is like a name for the task definition (having multiple versions)
  requires_compatibilities = ["FARGATE"]                # Serverless containers (no EC2 management)
  network_mode             = "awsvpc"                   # Each task gets its own network interface
  cpu                      = "256"                      # 0.25 vCPU
  memory                   = "512"                      # 512 MB RAM
  execution_role_arn       = var.app_execution_role_arn # IAM role used by ECS tasks to pull images from ECR and write logs. "What ECS needs to run your container"
  task_role_arn            = var.app_execution_role_arn # This reuses your existing execution role (which now has Bedrock permissions) as the task role too. "What your app needs to do its job"

  container_definitions = jsonencode([ # Container definitions are in JSON format, so we use jsonencode to convert from HCL to JSON
    {
      name        = var.app_name                          # Name of the container inside the task (the only container in this case)
      image       = "${local.ecr_url}:${var.app_version}" # Docker image from ECR repository of the app (latest tag)
      essential   = true                                  # If this container stops, stop the entire task
      environment = var.envars
      secrets     = var.secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.app_name}-task"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
      portMappings = [
        {
          containerPort = var.app_port # Port your app listens on inside container
          hostPort      = var.app_port # Port on task's network interface (must match containerPort in Fargate)
          # Port mapping concepts:
          # - containerPort = 80 → app listens on port 80 inside container
          # - hostPort = 80 → port 80 on the task's network interface
          # Why they're the same in Fargate:
          # - EC2 mode: Multiple containers share one host → hostPort can be different (e.g., container:80 → host:8080)
          # - Fargate mode: Each task has dedicated network → hostPort must match containerPort
          # Traffic flow:
          # - ALB sends request to task's ENI on port 80 (hostPort)
          # - Port 80 on ENI forwards to CONTAINER port 80 (containerPort)
          # - APP receives request on port 80
          #
        }
      ]
    }
  ])
}

# Create an ECS Service - maintains desired number of running tasks and registers them with ALB - similar to a deployment in Kubernetes
resource "aws_ecs_service" "this" {
  depends_on      = [terraform_data.push]            # Wait for Docker image to be pushed to ECR
  name            = "${var.app_name}-service"        # Name of the ECS service
  cluster         = var.cluster_arn                  # Which cluster to run in
  task_definition = aws_ecs_task_definition.this.arn # What containers to run
  desired_count   = 1                                # Keep 1 container running at all times
  launch_type     = "FARGATE"                        # Serverless container hosting
  network_configuration {
    subnets = var.subnet_ids # Which subnets to place containers in
    # security_groups must always be a list because the AWS API expects an array of security group IDs, even if you only have one
    security_groups  = [var.app_security_group_id] # The only one security group for the ECS tasks (containers), but wrapped in a list with brackets []
    assign_public_ip = var.is_public               # Give containers public IP for internet access
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn # Register containers with this target group. ECS only knows about TARGET GROUP. ECS Service doesn't know about ALB at all!
    container_name   = var.app_name                 # Which container within the task to route traffic to. Only ONE container per task can be registered with a specific target group
    container_port   = var.app_port                 # Which port of the container ALB should send traffic to
  }
}

# Here OPTIONAL - create a listener RULE - routes requests based on conditions
resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority     = var.lb_priority

  condition {
    path_pattern {
      values = [var.path_pattern]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

}

# Create a target group - shared registry where ECS registers healthy containers and ALB finds targets to route traffic to
resource "aws_lb_target_group" "this" {
  name        = "${var.app_name}-tg" # nginx-tg, apache-tg
  port        = var.app_port         # Port where containers listen
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Track containers by IP address (required for Fargate)

  # Lifecycle purpose:
  # - New target group gets created first
  # - Listener rule gets updated to use new target group
  # - ECS service gets updated to use new target group
  # - Old target group can now be safely deleted (no longer in use)
  lifecycle {
    create_before_destroy = true # Helps to handle destruction process
  }

  health_check {
    enabled             = true
    healthy_threshold   = 2                    # 2 successful checks = healthy
    unhealthy_threshold = 2                    # 2 failed checks = unhealthy
    timeout             = 5                    # Wait 5 seconds for response
    interval            = 30                   # Check every 30 seconds
    path                = var.healthcheck_path # Check this URL path
    matcher             = "200"                # Expect HTTP 200 response
  }
}