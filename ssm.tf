/*
 * SSM Parameter Store for Terraform Enterprise Configuration
 * 
 * Stores the TFE encryption password (shared across all instances).
 * This password is used to encrypt sensitive data at rest in TFE.
 * Must be identical across all nodes in an Active/Active deployment.
 */

# Generate a secure encryption password for TFE
resource "random_password" "tfe_enc_password" {
  length  = 32
  special = true

  # Ensure password meets TFE requirements (alphanumeric + special chars)
  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
  min_special = 4
}

# Store encryption password in SSM Parameter Store as SecureString
resource "aws_ssm_parameter" "tfe_enc_password" {
  name        = "/tfe/enc_password"
  description = "TFE encryption password (shared across all instances in Active/Active mode)"
  type        = "SecureString"
  value       = random_password.tfe_enc_password.result

  tags = {
    Name    = "/tfe/enc_password"
    service = "tfe"
    purpose = "encryption"
  }

  # Prevent rotation on every apply (keep existing value after initial creation)
  lifecycle {
    ignore_changes = [value]
  }
}
