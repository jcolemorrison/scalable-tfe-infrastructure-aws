#!/bin/bash
set -euo pipefail

###############################################################################
# Terraform Enterprise User Data Script
# 
# Installs Docker, Replicated, and configures TFE in External Services mode.
# Fetches RDS credentials at runtime from AWS Secrets Manager.
# 
# Assumptions:
# - Instance has IAM role with access to Secrets Manager, S3, and SSM
# - RDS Postgres, S3 bucket, and Redis are already provisioned
# - Security groups allow traffic between TFE instances and data services
###############################################################################

# Variables passed from Terraform (templatefile interpolation)
export AWS_REGION="${aws_region}"
export PROJECT_NAME="${project_name}"
export TFE_HOSTNAME="${hostname}"
export S3_BUCKET="${s3_bucket}"
export S3_REGION="${s3_region}"
export RDS_ADDRESS="${rds_address}"
export RDS_PORT="${rds_port}"
export RDS_DATABASE="${rds_database_name}"
export RDS_SECRET_ARN="${rds_secret_arn}"
export REDIS_HOST="${redis_host}"
export REDIS_PORT="${redis_port}"
export REDIS_USE_TLS="${redis_use_tls}"
export REDIS_USE_AUTH="${redis_use_auth}"

# Logging
LOG_FILE="/var/log/tfe_user_data.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== TFE User Data Script Started at $(date) ==="

###############################################################################
# 1. System Preparation
###############################################################################
echo "--- Updating system packages ---"
sudo apt-get update -y
sudo apt-get install -y \
  curl \
  jq \
  awscli \
  ca-certificates \
  gnupg \
  lsb-release

###############################################################################
# 2. Install Docker
###############################################################################
echo "--- Installing Docker ---"

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add ubuntu user to docker group (optional, for manual debugging)
sudo usermod -aG docker ubuntu

echo "--- Docker installed successfully ---"
docker --version

###############################################################################
# 3. Fetch RDS Credentials from Secrets Manager
###############################################################################
echo "--- Fetching RDS credentials from Secrets Manager ---"

# Fetch secret JSON from Secrets Manager using instance role with retry logic
# Do NOT echo the secret value to logs
MAX_RETRIES=3
RETRY_COUNT=0
RDS_SECRET_JSON=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  RDS_SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$RDS_SECRET_ARN" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text 2>/dev/null) && break
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "--- Retry $RETRY_COUNT/$MAX_RETRIES: Secrets Manager fetch failed, retrying in 5 seconds ---"
    sleep 5
  fi
done

if [ -z "$RDS_SECRET_JSON" ]; then
  echo "ERROR: Failed to fetch RDS credentials from Secrets Manager after $MAX_RETRIES attempts"
  exit 1
fi

# Parse username and password from JSON
# RDS-managed secrets have format: {"username":"...","password":"..."}
RDS_USERNAME=$(echo "$RDS_SECRET_JSON" | jq -r '.username')
RDS_PASSWORD=$(echo "$RDS_SECRET_JSON" | jq -r '.password')

# Validate that both username and password were extracted
if [ -z "$RDS_USERNAME" ] || [ "$RDS_USERNAME" == "null" ]; then
  echo "ERROR: Failed to extract RDS username from Secrets Manager"
  exit 1
fi

if [ -z "$RDS_PASSWORD" ] || [ "$RDS_PASSWORD" == "null" ]; then
  echo "ERROR: Failed to extract RDS password from Secrets Manager"
  exit 1
fi

echo "--- RDS credentials retrieved successfully (username and password hidden) ---"

###############################################################################
# 4. Fetch TFE Encryption Password from SSM Parameter Store
###############################################################################
echo "--- Fetching TFE encryption password from SSM Parameter Store ---"

# Fetch encryption password from SSM with retry logic
# This password MUST be shared across all TFE instances in Active/Active mode
MAX_RETRIES=3
RETRY_COUNT=0
ENC_PASSWORD=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  ENC_PASSWORD=$(aws ssm get-parameter \
    --name "/tfe/enc_password" \
    --region "$AWS_REGION" \
    --with-decryption \
    --query Parameter.Value \
    --output text 2>/dev/null) && break
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "--- Retry $RETRY_COUNT/$MAX_RETRIES: SSM Parameter fetch failed, retrying in 5 seconds ---"
    sleep 5
  fi
done

if [ -z "$ENC_PASSWORD" ] || [ "$ENC_PASSWORD" == "null" ]; then
  echo "ERROR: Failed to fetch TFE encryption password from SSM Parameter Store: /tfe/enc_password"
  echo "ERROR: This parameter must exist and be shared across all TFE instances."
  echo "ERROR: Create it in Terraform with: aws_ssm_parameter.tfe_enc_password"
  exit 1
fi

echo "--- TFE encryption password retrieved successfully (value hidden) ---"

###############################################################################
# 5. Install Replicated
###############################################################################
echo "--- Installing Replicated ---"

# Get private IP from instance metadata service (IMDS) using IMDSv2
# IMDSv2 requires a session token for security
echo "--- Fetching instance metadata using IMDSv2 ---"
TOKEN=$(curl -X PUT -s -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
  http://169.254.169.254/latest/api/token)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to retrieve IMDSv2 token"
  exit 1
fi

PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

if [ -z "$PRIVATE_IP" ]; then
  echo "ERROR: Failed to retrieve private IP from IMDS"
  exit 1
fi

echo "--- Instance private IP: $PRIVATE_IP ---"

# Download and run the Replicated install script
# Note: Using private-address only; nodes are in private subnets behind ALB
# Flags explained:
#   no-proxy: Don't use a proxy for Replicated traffic
#   private-address: Set the private IP for Replicated to bind to
#   public-address: Set to private IP (we're behind ALB, no direct public access)
#   no-docker: Don't install Docker (we already installed it)
# Using 'yes' to auto-answer any interactive prompts (like Docker version warnings)
echo "--- Downloading Replicated installer ---"
curl -o /tmp/install.sh https://install.terraform.io/ptfe/stable

echo "--- Running Replicated installer (non-interactive) ---"
yes | sudo bash /tmp/install.sh \
  no-proxy \
  private-address="$PRIVATE_IP" \
  public-address="$PRIVATE_IP" \
  no-docker

echo "--- Replicated installation complete ---"

###############################################################################
# 6. Configure TFE (External Services Mode)
###############################################################################
echo "--- Configuring TFE settings ---"

# Create TFE settings file for External Services mode
# Replicated expects this at /etc/tfe-settings.json
cat <<EOF | sudo tee /etc/tfe-settings.json
{
  "hostname": {
    "value": "$TFE_HOSTNAME"
  },
  "installation_type": {
    "value": "production"
  },
  "production_type": {
    "value": "external"
  },
  "enc_password": {
    "value": "$ENC_PASSWORD"
  },
  "pg_netloc": {
    "value": "$RDS_ADDRESS:$RDS_PORT"
  },
  "pg_dbname": {
    "value": "$RDS_DATABASE"
  },
  "pg_user": {
    "value": "$RDS_USERNAME"
  },
  "pg_password": {
    "value": "$RDS_PASSWORD"
  },
  "pg_extra_params": {
    "value": "sslmode=require"
  },
  "s3_bucket": {
    "value": "$S3_BUCKET"
  },
  "s3_region": {
    "value": "$S3_REGION"
  },
  "s3_use_instance_profile": {
    "value": "1"
  },
  "redis_host": {
    "value": "$REDIS_HOST"
  },
  "redis_port": {
    "value": "$REDIS_PORT"
  },
  "redis_use_tls": {
    "value": "$REDIS_USE_TLS"
  },
  "redis_use_password": {
    "value": "$REDIS_USE_AUTH"
  }
}
EOF

# Set secure permissions on settings file (contains secrets)
sudo chmod 600 /etc/tfe-settings.json

# Create symlink for legacy compatibility
sudo ln -sf /etc/tfe-settings.json /etc/ptfe-settings.json

echo "--- TFE settings configured ---"

###############################################################################
# 7. Start TFE Application
###############################################################################
echo "--- Starting TFE application ---"

# Wait for Replicated to be ready and replicatedctl to be available
echo "--- Waiting for Replicated to be ready ---"
MAX_WAIT=300 # 5 minutes
ELAPSED=0
while ! command -v replicatedctl &> /dev/null; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "ERROR: Replicated did not become ready within $MAX_WAIT seconds"
    exit 1
  fi
  echo "--- Waiting for replicatedctl to be available... ($ELAPSED/$MAX_WAIT seconds) ---"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

echo "--- Replicated is ready ---"

###############################################################################
# 7a. Fetch and Load TFE License
###############################################################################
echo "--- Fetching TFE license from Secrets Manager ---"

# Fetch license from Secrets Manager with retry logic
MAX_RETRIES=3
RETRY_COUNT=0
LICENSE_JSON=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  LICENSE_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "/tfe/license" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text 2>/dev/null) && break
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "--- Retry $RETRY_COUNT/$MAX_RETRIES: License fetch failed, retrying in 5 seconds ---"
    sleep 5
  fi
done

if [ -z "$LICENSE_JSON" ]; then
  echo "ERROR: Failed to fetch TFE license from Secrets Manager after $MAX_RETRIES attempts"
  echo "ERROR: Make sure the secret /tfe/license exists and contains your license content"
  exit 1
fi

# Extract license content from JSON
LICENSE_CONTENT=$(echo "$LICENSE_JSON" | jq -r '.license')

if [ -z "$LICENSE_CONTENT" ] || [ "$LICENSE_CONTENT" == "null" ]; then
  echo "ERROR: Failed to extract license content from Secrets Manager"
  echo "ERROR: Secret format should be: {\"license\": \"<license-content>\"}"
  exit 1
fi

echo "--- TFE license retrieved successfully ---"

# Save license to file
echo "$LICENSE_CONTENT" | sudo tee /tmp/tfe-license.rli > /dev/null

# Load license into Replicated
echo "--- Loading TFE license into Replicated ---"
sudo replicatedctl license-load < /tmp/tfe-license.rli

# Clean up license file (contains sensitive data)
sudo rm -f /tmp/tfe-license.rli

echo "--- TFE license loaded successfully ---"

###############################################################################
# 7b. Import TFE Configuration and Start Application
###############################################################################
# Import TFE settings and apply configuration
echo "--- Importing TFE settings ---"
cat /etc/tfe-settings.json | sudo replicatedctl app-config import

echo "--- Applying TFE configuration ---"
sudo replicatedctl app apply-config -y

# Wait for TFE application to start
echo "--- Waiting for TFE application to start ---"
MAX_WAIT=600 # 10 minutes
ELAPSED=0
APP_READY=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
  APP_STATUS=$(sudo replicatedctl app status 2>/dev/null || echo "unknown")
  
  if echo "$APP_STATUS" | grep -qE "ready|started|running"; then
    APP_READY=true
    break
  fi
  
  echo "--- TFE app status: $APP_STATUS (waiting... $ELAPSED/$MAX_WAIT seconds) ---"
  sleep 15
  ELAPSED=$((ELAPSED + 15))
done

if [ "$APP_READY" = true ]; then
  echo "--- TFE application started successfully ---"
else
  echo "WARNING: TFE application did not report ready status within $MAX_WAIT seconds"
  echo "WARNING: Check Replicated admin console or logs for details"
fi

###############################################################################
# 8. Install and Configure CloudWatch Agent
###############################################################################
echo "--- Installing CloudWatch Agent ---"

# Download and install CloudWatch Agent
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb

# Create CloudWatch Agent configuration
cat <<CWCONFIG | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/tfe_user_data.log",
            "log_group_name": "/aws/tfe/$PROJECT_NAME",
            "log_stream_name": "{instance_id}/user-data",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/aws/tfe/$PROJECT_NAME",
            "log_stream_name": "{instance_id}/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "/aws/tfe/$PROJECT_NAME",
            "log_stream_name": "{instance_id}/cloud-init",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWCONFIG

# Start CloudWatch Agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "--- CloudWatch Agent installed and started ---"
echo "--- Logs will be available in CloudWatch Logs: /aws/tfe/$PROJECT_NAME ---"

###############################################################################
# Completion
###############################################################################
echo "=== TFE User Data Script Completed at $(date) ==="
echo ""
echo "--- TFE Installation Summary ---"
echo "Hostname: $TFE_HOSTNAME"
echo "Instance Private IP: $PRIVATE_IP"
echo ""
echo "--- Next Steps ---"
echo "1. Access TFE web UI: https://$TFE_HOSTNAME (via ALB once DNS is configured)"
echo "2. Replicated admin console: https://$PRIVATE_IP:8800 (access via SSM Session Manager or VPN)"
echo "3. Upload TFE license file via admin console"
echo "4. Complete initial admin user setup via TFE web UI"
echo ""
echo "--- Important Notes ---"
echo "- DNS record for $TFE_HOSTNAME should point to the ALB DNS name, not this instance IP"
echo "- Admin console (port 8800) is NOT exposed via ALB; use SSM Session Manager for access:"
echo "  aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters 'portNumber=8800,localPortNumber=8800'"
echo "- CloudWatch Agent installation pending (waiting for log group creation)"
echo ""
