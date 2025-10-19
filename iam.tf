/*
 * IAM Role and Instance Profile for Terraform Enterprise EC2 Instances
 * 
 * Provides least-privilege access to:
 * - Secrets Manager (RDS password and future TFE secrets)
 * - SSM Parameter Store (TFE configuration)
 * - S3 (TFE objects bucket only)
 * - CloudWatch Logs (TFE application logs)
 * - Systems Manager (Session Manager for secure access, no SSH)
 */

# Get current AWS account ID and region for ARN construction
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM Role for TFE EC2 instances
resource "aws_iam_role" "tfe_instance" {
  name        = "${var.project_name}-instance-role"
  description = "IAM role for Terraform Enterprise EC2 instances"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-instance-role"
    service = "tfe"
    layer   = "application"
  }
}

# Inline policy with least-privilege permissions
resource "aws_iam_role_policy" "tfe_instance" {
  name = "${var.project_name}-instance-policy"
  role = aws_iam_role.tfe_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Secrets Manager - Read RDS master password (managed by RDS)
        Sid    = "RDSMasterSecretRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_db_instance.tfe.master_user_secret[0].secret_arn
        ]
      },
      {
        # Secrets Manager - Read future TFE application secrets
        # (e.g., TFE license, encryption password, Redis auth token)
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:/tfe/*"
        ]
      },
      {
        # SSM Parameter Store - Read TFE configuration parameters
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/tfe/*"
        ]
      },
      # Uncomment if using customer-managed KMS keys for Secrets Manager or SSM
      # {
      #   Sid    = "KMSDecrypt"
      #   Effect = "Allow"
      #   Action = [
      #     "kms:Decrypt",
      #     "kms:DescribeKey"
      #   ]
      #   Resource = [
      #     "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
      #   ]
      #   Condition = {
      #     StringEquals = {
      #       "kms:ViaService" = [
      #         "secretsmanager.${data.aws_region.current.name}.amazonaws.com",
      #         "ssm.${data.aws_region.current.name}.amazonaws.com"
      #       ]
      #     }
      #   }
      # },
      {
        # S3 - List bucket (for TFE object storage)
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.tfe_objects.arn
        ]
      },
      {
        # S3 - Object operations (scoped to TFE bucket only)
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.tfe_objects.arn}/*"
        ]
      },
      # NOTE: Temporary wide scope for CloudWatch Logs. When we add a named log group
      # (e.g., /tfe/${var.project_name}) and the CW Agent in the Launch Template,
      # we will tighten CreateLogStream/PutLogEvents to the specific log group ARN.
      {
        # CloudWatch Logs - Create log groups (requires wildcard resource)
        Sid    = "CloudWatchLogsCreateGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        # CloudWatch Logs - Write to log streams
        Sid    = "CloudWatchLogsStreams"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for Systems Manager (Session Manager)
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.tfe_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile to attach the role to EC2 instances
resource "aws_iam_instance_profile" "tfe" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.tfe_instance.name

  tags = {
    Name    = "${var.project_name}-instance-profile"
    service = "tfe"
    layer   = "application"
  }
}
