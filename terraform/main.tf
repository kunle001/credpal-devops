terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state – replace bucket/key/region with your values before applying
  backend "s3" {
    bucket         = "credpal-terraform-state"
    key            = "credpal-app/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "credpal-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "credpal-app"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ─── Data Sources ────────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}
