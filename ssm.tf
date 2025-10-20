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

# TFE License File stored in Secrets Manager
# You'll need to manually upload your .rli license file content to this secret
resource "aws_secretsmanager_secret" "tfe_license" {
  name        = "/tfe/license"
  description = "TFE license file content (.rli file)"

  tags = {
    Name    = "/tfe/license"
    service = "tfe"
    purpose = "license"
  }
}

# Placeholder secret version - you'll need to update this with your actual license
resource "aws_secretsmanager_secret_version" "tfe_license" {
  secret_id = aws_secretsmanager_secret.tfe_license.id
  secret_string = jsonencode({
    license = "REPLACE_WITH_YOUR_LICENSE_CONTENT"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

