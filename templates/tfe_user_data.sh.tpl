#!/bin/bash
set -euo pipefail

# TFE User Data - Installs Docker, Replicated, and configures TFE in External Services mode
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
export LICENSE_SECRET_ARN="${license_secret_arn}"

LOG_FILE="/var/log/tfe_user_data.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== TFE User Data Started at $(date) ==="

# System Preparation
echo "--- Updating packages ---"
sudo apt-get update -y
sudo apt-get install -y curl jq awscli ca-certificates gnupg lsb-release

# Install Docker
echo "--- Installing Docker ---"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
docker --version

# Fetch RDS Credentials
echo "--- Fetching RDS credentials ---"
MAX_RETRIES=3
RETRY_COUNT=0
RDS_SECRET_JSON=""
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  RDS_SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text 2>/dev/null) && break
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && sleep 5
done
[ -z "$RDS_SECRET_JSON" ] && echo "ERROR: Failed to fetch RDS credentials" && exit 1
RDS_USERNAME=$(echo "$RDS_SECRET_JSON" | jq -r '.username')
RDS_PASSWORD=$(echo "$RDS_SECRET_JSON" | jq -r '.password')
[ -z "$RDS_USERNAME" ] || [ "$RDS_USERNAME" == "null" ] && echo "ERROR: Failed to extract RDS username" && exit 1
[ -z "$RDS_PASSWORD" ] || [ "$RDS_PASSWORD" == "null" ] && echo "ERROR: Failed to extract RDS password" && exit 1

# Fetch TFE Encryption Password
echo "--- Fetching encryption password ---"
MAX_RETRIES=3
RETRY_COUNT=0
ENC_PASSWORD=""
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  ENC_PASSWORD=$(aws ssm get-parameter --name "/tfe/enc_password" --region "$AWS_REGION" --with-decryption --query Parameter.Value --output text 2>/dev/null) && break
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && sleep 5
done
[ -z "$ENC_PASSWORD" ] || [ "$ENC_PASSWORD" == "null" ] && echo "ERROR: Failed to fetch encryption password" && exit 1

# Install Replicated
echo "--- Installing Replicated ---"
TOKEN=$(curl -X PUT -s -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" http://169.254.169.254/latest/api/token)
[ -z "$TOKEN" ] && echo "ERROR: Failed to retrieve IMDSv2 token" && exit 1
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
[ -z "$PRIVATE_IP" ] && echo "ERROR: Failed to retrieve private IP" && exit 1

curl -o /tmp/install.sh https://install.terraform.io/ptfe/stable
(yes || true) | sudo bash /tmp/install.sh no-proxy private-address="$PRIVATE_IP" public-address="$PRIVATE_IP" no-docker

# Configure TFE
cat <<EOF | sudo tee /etc/tfe-settings.json
{"hostname":{"value":"$TFE_HOSTNAME"},"installation_type":{"value":"production"},"production_type":{"value":"external"},"enc_password":{"value":"$ENC_PASSWORD"},"pg_netloc":{"value":"$RDS_ADDRESS:$RDS_PORT"},"pg_dbname":{"value":"$RDS_DATABASE"},"pg_user":{"value":"$RDS_USERNAME"},"pg_password":{"value":"$RDS_PASSWORD"},"pg_extra_params":{"value":"sslmode=require"},"s3_bucket":{"value":"$S3_BUCKET"},"s3_region":{"value":"$S3_REGION"},"s3_use_instance_profile":{"value":"1"},"redis_host":{"value":"$REDIS_HOST"},"redis_port":{"value":"$REDIS_PORT"},"redis_use_tls":{"value":"$REDIS_USE_TLS"},"redis_use_password":{"value":"$REDIS_USE_AUTH"}}
EOF

sudo chmod 600 /etc/tfe-settings.json
sudo ln -sf /etc/tfe-settings.json /etc/ptfe-settings.json

# Wait for Replicated
MAX_WAIT=300
ELAPSED=0
while ! command -v replicatedctl &> /dev/null; do
  [ $ELAPSED -ge $MAX_WAIT ] && echo "ERROR: Replicated not ready" && exit 1
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

# Wait for Replicated socket and API
echo "--- Waiting for Replicated API ---"
MAX_WAIT=180
ELAPSED=0
API_READY=false
while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Check if socket exists and system status works (doesn't require license)
  if [ -S /var/run/replicated/replicated-cli.sock ] && sudo replicatedctl system status &> /dev/null; then
    API_READY=true
    break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
[ "$API_READY" = false ] && echo "ERROR: Replicated API not ready" && exit 1

# Fetch and Load License
echo "--- Fetching license ---"
MAX_RETRIES=3
RETRY_COUNT=0
LICENSE_JSON=""
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  LICENSE_JSON=$(aws secretsmanager get-secret-value --secret-id "$LICENSE_SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text 2>/dev/null) && break
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && sleep 5
done
[ -z "$LICENSE_JSON" ] && echo "ERROR: Failed to fetch license" && exit 1

LICENSE_CONTENT=$(echo "$LICENSE_JSON" | jq -r '.license')
[ -z "$LICENSE_CONTENT" ] || [ "$LICENSE_CONTENT" == "null" ] && echo "ERROR: Failed to extract license" && exit 1
echo "$LICENSE_CONTENT" | grep -q "^eyJ" && LICENSE_CONTENT=$(echo "$LICENSE_CONTENT" | base64 -d)
echo "$LICENSE_CONTENT" | sudo tee /tmp/tfe-license.rli > /dev/null
sudo replicatedctl license-load < /tmp/tfe-license.rli
sudo rm -f /tmp/tfe-license.rli

# Import Config and Start
cat /etc/tfe-settings.json | sudo replicatedctl app-config import
sudo replicatedctl app apply-config -y

# Wait for TFE
MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  APP_STATUS=$(sudo replicatedctl app status 2>/dev/null || echo "unknown")
  echo "$APP_STATUS" | grep -qE "ready|started|running" && break
  sleep 15
  ELAPSED=$((ELAPSED + 15))
done

# Install CloudWatch Agent
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb
cat <<CWCONFIG | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json
{"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/tfe_user_data.log","log_group_name":"/aws/tfe/$PROJECT_NAME","log_stream_name":"{instance_id}/user-data","timezone":"UTC"},{"file_path":"/var/log/syslog","log_group_name":"/aws/tfe/$PROJECT_NAME","log_stream_name":"{instance_id}/syslog","timezone":"UTC"},{"file_path":"/var/log/cloud-init-output.log","log_group_name":"/aws/tfe/$PROJECT_NAME","log_stream_name":"{instance_id}/cloud-init","timezone":"UTC"}]}}}}
CWCONFIG
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "=== TFE User Data Completed at $(date) ==="