#!/bin/bash
set -euo pipefail

# TFE User Data - Docker Compose deployment with External Services mode
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
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

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

# Fetch TFE Encryption Password from SSM
echo "--- Fetching encryption password ---"
RETRY_COUNT=0
ENC_PASSWORD=""
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  ENC_PASSWORD=$(aws ssm get-parameter --name "/tfe/enc_password" --region "$AWS_REGION" --with-decryption --query Parameter.Value --output text 2>/dev/null) && break
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && sleep 5
done
[ -z "$ENC_PASSWORD" ] || [ "$ENC_PASSWORD" == "null" ] && echo "ERROR: Failed to fetch encryption password" && exit 1

# Fetch TFE License from Secrets Manager
echo "--- Fetching TFE license ---"
RETRY_COUNT=0
LICENSE_JSON=""
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  LICENSE_JSON=$(aws secretsmanager get-secret-value --secret-id "$LICENSE_SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text 2>/dev/null) && break
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && sleep 5
done
[ -z "$LICENSE_JSON" ] && echo "ERROR: Failed to fetch license" && exit 1

export TFE_LICENSE=$(echo "$LICENSE_JSON" | jq -r '.license')
[ -z "$TFE_LICENSE" ] || [ "$TFE_LICENSE" == "null" ] && echo "ERROR: Failed to extract license" && exit 1

# Get instance private IP
echo "--- Getting instance metadata ---"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
[ -z "$PRIVATE_IP" ] && echo "ERROR: Failed to get private IP" && exit 1

# Create TFE environment file
echo "--- Creating TFE configuration ---"
sudo mkdir -p /etc/tfe
sudo tee /etc/tfe/tfe.env > /dev/null << EOF
TFE_LICENSE=$TFE_LICENSE
TFE_HOSTNAME=$TFE_HOSTNAME
TFE_IACT_SUBNETS=0.0.0.0/0
TFE_IACT_TIME_LIMIT=60
TFE_OPERATIONAL_MODE=active-active
TFE_ENCRYPTION_PASSWORD=$ENC_PASSWORD
TFE_DISK_CACHE_VOLUME_NAME=tfe-cache
TFE_TLS_CERT_FILE=/etc/ssl/private/terraform-enterprise/cert.pem
TFE_TLS_KEY_FILE=/etc/ssl/private/terraform-enterprise/key.pem
TFE_TLS_CA_BUNDLE_FILE=/etc/ssl/private/terraform-enterprise/bundle.pem
TFE_DATABASE_HOST=$RDS_ADDRESS
TFE_DATABASE_NAME=$RDS_DATABASE
TFE_DATABASE_USER=$RDS_USERNAME
TFE_DATABASE_PASSWORD=$RDS_PASSWORD
TFE_DATABASE_PARAMETERS=sslmode=require
TFE_OBJECT_STORAGE_TYPE=s3
TFE_OBJECT_STORAGE_S3_BUCKET=$S3_BUCKET
TFE_OBJECT_STORAGE_S3_REGION=$S3_REGION
TFE_OBJECT_STORAGE_S3_USE_INSTANCE_PROFILE=true
TFE_VAULT_CLUSTER_ADDRESS=https://$PRIVATE_IP:8201
TFE_REDIS_HOST=$REDIS_HOST
TFE_REDIS_PORT=$REDIS_PORT
TFE_REDIS_USE_TLS=$REDIS_USE_TLS
TFE_REDIS_USE_AUTH=$REDIS_USE_AUTH
EOF

sudo chmod 600 /etc/tfe/tfe.env

# Create self-signed certificate for TFE
echo "--- Creating TLS certificates ---"
sudo mkdir -p /etc/ssl/private/terraform-enterprise
sudo openssl req -x509 -nodes -newkey rsa:4096 -keyout /etc/ssl/private/terraform-enterprise/key.pem -out /etc/ssl/private/terraform-enterprise/cert.pem -days 365 -subj "/CN=$TFE_HOSTNAME" 2>/dev/null
sudo cp /etc/ssl/private/terraform-enterprise/cert.pem /etc/ssl/private/terraform-enterprise/bundle.pem
sudo chmod 600 /etc/ssl/private/terraform-enterprise/*.pem

# Create docker-compose.yml
echo "--- Creating docker-compose configuration ---"
sudo tee /etc/tfe/docker-compose.yml > /dev/null << 'DOCKEREOF'
version: "3.9"
services:
  tfe:
    image: images.releases.hashicorp.com/hashicorp/terraform-enterprise:v202410-1
    env_file: /etc/tfe/tfe.env
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - type: volume
        source: tfe-cache
        target: /var/cache/tfe-task-worker/terraform
      - type: bind
        source: /var/log/tfe
        target: /var/log/terraform-enterprise
      - type: bind
        source: /etc/ssl/private/terraform-enterprise
        target: /etc/ssl/private/terraform-enterprise
    cap_add:
      - CAP_IPC_LOCK
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  tfe-cache:
    name: tfe-cache
DOCKEREOF

# Create log directory
sudo mkdir -p /var/log/tfe
sudo chmod 755 /var/log/tfe

# Authenticate to HashiCorp container registry using license
echo "--- Authenticating to container registry ---"
echo "$TFE_LICENSE" | sudo docker login images.releases.hashicorp.com --username terraform --password-stdin

# Start TFE
echo "--- Starting TFE ---"
cd /etc/tfe
sudo docker compose up -d

# Wait for TFE to be healthy
echo "--- Waiting for TFE to become healthy ---"
MAX_WAIT=600
ELAPSED=0
TFE_HEALTHY=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
  if curl -sfk https://localhost/_health_check > /dev/null 2>&1; then
    TFE_HEALTHY=true
    echo "TFE is healthy!"
    break
  fi
  
  if [ $((ELAPSED % 60)) -eq 0 ]; then
    echo "Still waiting... ($${ELAPSED}s elapsed)"
    sudo docker compose ps
  fi
  
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [ "$TFE_HEALTHY" = false ]; then
  echo "WARNING: TFE health check did not pass within $MAX_WAIT seconds"
  echo "Container logs:"
  sudo docker compose logs --tail=50
else
  echo "TFE is ready at https://$TFE_HOSTNAME"
fi

# Install CloudWatch Agent
echo "--- Installing CloudWatch Agent ---"
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
rm -f amazon-cloudwatch-agent.deb

sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json > /dev/null << EOF
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
            "file_path": "/var/log/tfe/*.log",
            "log_group_name": "/aws/tfe/$PROJECT_NAME",
            "log_stream_name": "{instance_id}/tfe-app",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "=== TFE User Data Completed at $(date) ==="