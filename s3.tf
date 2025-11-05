/*
 * S3 Bucket for Terraform Enterprise Object Storage
 * 
 * Stores Terraform state files, run artifacts, and other TFE objects.
 * Uses a random suffix to ensure global uniqueness.
 */

resource "random_id" "s3_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tfe_objects" {
  bucket = "tfe-objects-${random_id.s3_suffix.hex}"

  # Prevent accidental deletion in production
  # Set to true for dev/test environments
  force_destroy = true

  tags = {
    Name    = "tfe-objects-${random_id.s3_suffix.hex}"
    service = "tfe"
    purpose = "object-storage"
  }
}

# Enable versioning for object recovery
resource "aws_s3_bucket_versioning" "tfe_objects" {
  bucket = aws_s3_bucket.tfe_objects.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "tfe_objects" {
  bucket = aws_s3_bucket.tfe_objects.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable default encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfe_objects" {
  bucket = aws_s3_bucket.tfe_objects.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
