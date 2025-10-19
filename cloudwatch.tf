/*
 * CloudWatch Log Group for Terraform Enterprise
 * 
 * Centralized logging for TFE application and system logs.
 * CloudWatch Agent on EC2 instances ships logs to this group.
 */

resource "aws_cloudwatch_log_group" "tfe" {
  name              = "/aws/tfe/${var.project_name}"
  retention_in_days = 30 # Adjust as needed: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653

  tags = {
    Name    = "/aws/tfe/${var.project_name}"
    service = "tfe"
    purpose = "logging"
  }
}
