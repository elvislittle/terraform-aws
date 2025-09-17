# OUTPUTS OF INFRASTRUCTURE MODULE

# Output ARN of ECS Task Execution Role
output "app_execution_role_arn" {
  description = "ARN of the ECS Task Execution Role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

# Output subnet IDs
output "aws_subnet_ids" {
  description = "List of subnet IDs"
  value       = [for subnet in aws_subnet.this : subnet.id]
}

# Output Security Group ID for ECS tasks
output "app_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

# Output ALB Target Group ARN
output "alb_target_group_arn" {
  description = "ARN of the ALB Target Group"
  value       = aws_lb_target_group.this.arn
}

# Output ALB DNS name
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}