variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "domain_name" {
  description = "Fully-qualified domain name (e.g. api.credpal.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID. Provide to enable automatic DNS validation and A record creation. Leave empty to manage DNS manually."
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  type    = bool
  default = false
}

variable "enable_waf" {
  description = "Attach an AWS WAF WebACL with managed rule groups to the ALB"
  type        = bool
  default     = true
}
