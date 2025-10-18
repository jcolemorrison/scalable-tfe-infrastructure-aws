terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.17.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.58"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}

data "aws_caller_identity" "current" {}

output "whoami" {
  value = data.aws_caller_identity.current.arn
}