variable "aws_region" {
  description = "Default AWS region for deploying Terraform Enterprise infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "default_tags" {
  description = "Default tags applied to all AWS resources via the provider's default_tags."
  type        = map(string)
  default = {
    project = "scalable-tfe"
  }
}