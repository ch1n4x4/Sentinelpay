variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS resources will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by ECS Fargate tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the Application Load Balancer"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group used by the ECS service"
  type        = string
}

variable "container_image" {
  description = "Docker image for the ECS task definition"
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Port on which the container listens"
  type        = number
  default     = 80
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudWatch Logs"
  type        = string
}

variable "name_prefix" {
  description = "Optional prefix used for naming compute resources"
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region used by ECS CloudWatch logging"
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Common tags applied to compute resources"
  type        = map(string)
  default     = {}
}
variable "vpc_cidr" {
  description = "CIDR block of the VPC used to restrict ECS outbound traffic"
  type        = string
}

variable "env_vars" {
  description = "Environment variables for the container"
  type        = list(object({
    name  = string
    value = string
  }))
  default     = []
}