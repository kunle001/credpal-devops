variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production."
  }
}

variable "app_name" {
  description = "Application name used as a prefix for all resources"
  type        = string
  default     = "credpal-app"
}

variable "app_image" {
  description = "Docker image URI (e.g. ghcr.io/org/repo:sha-abc123)"
  type        = string
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "app_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "fargate_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "credpal_db"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Registered domain name for the ACM certificate (e.g. api.credpal.com)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
