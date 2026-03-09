variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "app_image" {
  description = "Docker image URI set by CI/CD (e.g. ghcr.io/org/repo:sha-abc123)"
  type        = string
}

variable "domain_name" {
  type = string
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

variable "db_name" {
  type    = string
  default = "credpal_db"
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "alarm_email" {
  type    = string
  default = ""
}

variable "github_repo" {
  description = "GitHub repo in org/repo format (e.g. myorg/credpal-devops)"
  type        = string
}
