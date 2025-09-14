# Authentik Development Environment Deployment on AWS

This directory contains all the necessary files and scripts to deploy Authentik to AWS for development purposes with an external RDS PostgreSQL database and SSL certificate for domain `dev-auth.testimonialtree.com`.

## Overview

The deployment consists of:
- **RDS PostgreSQL**: External database for Authentik
- **ECS Fargate**: Container orchestration for Authentik server and worker
- **Application Load Balancer**: Load balancing with SSL termination
- **Route 53**: DNS management for the domain
- **AWS Certificate Manager**: SSL certificates
- **Secrets Manager**: Secure credential storage

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Docker installed** for building images
3. **Domain ownership**: Access to configure DNS for `testimonialtree.com`
4. **AWS Account**: With permissions for VPC, ECS, RDS, ALB, Route 53, etc.

## Quick Start

### 1. Deploy the Terraform CI/CD Pipeline

```bash
# From the repo root
./deploy/dev/deploy-pipeline.sh
```

This provisions ALB, ECS, RDS, ECR, CloudWatch, and CodePipeline/CodeBuild into the existing VPC, then prints useful outputs (ALB DNS, RDS endpoint, etc.).

### 2. Configure Environment

```bash
# Get values from Terraform outputs
cd deploy/dev/terraform
terraform output

# Example: capture RDS host (trim :port)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint | cut -d: -f1)
cd ../../..

# Update .env.dev with actual RDS endpoint (if not already set)
sed -i '' "s/your-rds-endpoint.region.rds.amazonaws.com/$RDS_ENDPOINT/g" .env.dev

# Generate a secure secret key (only if you need a new one)
AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)
sed -i '' "s/dev-change-this-to-a-secure-random-key-64-characters-long-minimum/$AUTHENTIK_SECRET_KEY/g" .env.dev

# Create or update unified JSON secret in Secrets Manager from your .env.dev
bash deploy/dev/scripts/secrets-sync.sh
```

### 3. Build and Push or Use the Pipeline

Option A — Use CodePipeline (recommended):
- Package and upload source, then start the pipeline

```bash
./deploy/dev/upload-source.sh
# In the AWS Console: CodePipeline → your pipeline → Release change
```

Option B — Build/push locally (for custom image testing):

```bash
chmod +x deploy/dev/scripts/*.sh
./deploy/dev/scripts/build-and-push.sh
```

### 4. Run Database Migrations

```bash
./deploy/dev/scripts/run-migrations.sh
```

### 5. Deploy/Verify Service

```bash
# Preferred: let CodePipeline deploy to ECS
# Optional: manual emergency deploy to ECS
./deploy/dev/scripts/manual-deploy.sh
```

## Detailed Configuration

### Environment & Secrets

Update `.env.dev` with your specific configuration:

```bash
# Required: Replace with actual RDS endpoint
PG_HOST=your-rds-endpoint.region.rds.amazonaws.com
PG_PASS=your-secure-rds-password  # Will be stored in Secrets Manager

Secrets are stored in a single JSON secret in AWS Secrets Manager: `authentik-dev/app-config` with keys:
- `AUTHENTIK_SECRET_KEY`
- `AUTHENTIK_POSTGRESQL__HOST`
- `AUTHENTIK_POSTGRESQL__USER`
- `AUTHENTIK_POSTGRESQL__PASSWORD`
- `AUTHENTIK_POSTGRESQL__NAME`

To create/update this secret from existing values:
`bash deploy/dev/scripts/secrets-sync.sh`

# Domain configuration
AUTHENTIK_COOKIE_DOMAIN=dev-auth.testimonialtree.com
```

### SSL Certificate Setup

See [SSL_SETUP.md](SSL_SETUP.md) for detailed SSL configuration options. For this environment, an ACM certificate is created by Terraform; complete DNS validation from the AWS Console, then point your domain A record to the ALB DNS from Terraform outputs.

### Notes on Infrastructure

The Terraform in `deploy/dev/terraform` uses an existing VPC and subnets, and provisions ALB, ECS (Fargate), RDS, ECR, CloudWatch, Secrets, and CodePipeline/CodeBuild.

## File Structure

```
deploy/dev/
├── README.md                    # This file
├── PIPELINE-README.md           # CI/CD pipeline details
├── SSL_SETUP.md                 # SSL certificate configuration guide
├── .env.dev                     # Environment variables (configure this)
├── docker-compose.dev.yml       # Docker Compose for local testing
├── deploy-pipeline.sh           # Wrapper to init/plan/apply Terraform
├── upload-source.sh             # Package + upload source to S3 (pipeline)
├── scripts/
│   ├── build-and-push.sh        # Build and push Docker image to ECR
│   ├── run-migrations.sh        # Run database migrations
│   ├── manual-deploy.sh         # Manual/Emergency deploy to ECS Fargate
│   └── secrets-sync.sh          # Create/update unified JSON app secret
└── terraform/                   # Terraform for ALB/ECS/RDS/ECR/CodePipeline
```

## Monitoring and Logs

### CloudWatch Logs

Logs are automatically sent to CloudWatch:
- Log Group: `/ecs/authentik-dev`
- Streams: Container logs for server, worker, and redis

### Health Checks

The deployment includes health checks:
- **ECS Task Health Check**: Checks Authentik server health endpoint
- **ALB Health Check**: Monitors target group health
- **RDS Monitoring**: Database performance insights

### View Logs

```bash
# View recent logs
aws logs tail /ecs/authentik-dev --follow --region $AWS_REGION

# View specific container logs
aws logs filter-log-events \
  --log-group-name /ecs/authentik-dev \
  --filter-pattern "authentik-server" \
  --region $AWS_REGION
```

## Troubleshooting

### Common Issues

1. **Database Connection Issues**:
   ```bash
   # Test database connectivity
   docker run --rm --env-file .env.dev postgres:16-alpine \
     psql -h $PG_HOST -U authentik -d authentik_dev -c "SELECT version();"
   ```

2. **SSL Certificate Validation**:
   - Ensure DNS records are properly configured
   - Check certificate status in ACM console
   - Verify domain ownership

3. **ECS Task Failures**:
   ```bash
   # Check ECS task status
   aws ecs describe-tasks \
     --cluster authentik-dev \
     --tasks $(aws ecs list-tasks --cluster authentik-dev --query 'taskArns[0]' --output text)
   ```

4. **Load Balancer Issues**:
   ```bash
   # Check target group health (using Terraform output)
   aws elbv2 describe-target-health \
     --target-group-arn $(cd deploy/dev/terraform && terraform output -raw target_group_arn)
   ```

### Debug Commands

```bash
# Terraform outputs
cd deploy/dev/terraform && terraform output && cd ../../..

# ECS service status
aws ecs describe-services --cluster authentik-dev --services authentik-dev

# Target group health
aws elbv2 describe-target-health \
  --target-group-arn $(cd deploy/dev/terraform && terraform output -raw target_group_arn)

# Logs
aws logs tail /ecs/authentik-dev --follow

# Test connectivity to services
curl -I https://dev-auth.testimonialtree.com/-/health/ready/
```

## Cost Optimization

For development environment:
- Use `db.t3.micro` for RDS (can be included in free tier)
- Use minimal ECS Fargate resources (0.25 vCPU, 0.5 GB memory)
- Enable ALB deletion protection: false
- Set RDS deletion protection: false
- Use single-AZ RDS deployment

## Cleanup

To destroy the development environment:

```bash
cd deploy/dev/terraform
terraform destroy

# Optional: remove ECR images
aws ecr batch-delete-image \
  --repository-name authentik-dev \
  --image-ids imageTag=latest

# Clean up local files
rm -f deploy/dev/.env.image
```

## Security Considerations

- All database credentials are stored in AWS Secrets Manager
- Security groups follow least-privilege access
- RDS instance is in private subnets
- SSL/TLS termination at load balancer level
- Container logs do not contain sensitive information

## Initial Admin Setup

After deployment, you need to create the initial admin user (akadmin):

### Via Web Interface (Recommended)

1. **Navigate to the initial setup page**: https://dev-auth.testimonialtree.com/if/flow/initial-setup/
2. **Fill out the form**:
   - Email address for the admin user
   - Strong password (store it securely in a password manager!)
3. **Click "Continue"** to complete the setup

**Note**: This initial setup flow is only available before the first admin user is created and will automatically disappear after setup is complete.

### Via Command Line (Alternative)

If the web interface is unavailable, you can use the helper script:

```bash
# Run the admin creation script
./scripts/create-admin.sh
```

Or run the commands manually:

```bash
# Scale down service temporarily
aws ecs update-service --cluster authentik-dev --service authentik-dev --desired-count 0

# Create admin group
aws ecs run-task \
  --cluster authentik-dev \
  --task-definition authentik-dev:27 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-0853305679f0dfb1e,subnet-03488d1eba867dc11],securityGroups=[sg-0e4002f14830ba443],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"authentik-server","command":["ak","create_admin_group"]},{"name":"authentik-worker","command":["sleep","60"]}]}'

# Set admin password (this will prompt for password)
aws ecs run-task \
  --cluster authentik-dev \
  --task-definition authentik-dev:27 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-0853305679f0dfb1e,subnet-03488d1eba867dc11],securityGroups=[sg-0e4002f14830ba443],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"authentik-server","command":["ak","changepassword","akadmin"]},{"name":"authentik-worker","command":["sleep","60"]}]}'

# Scale service back up
aws ecs update-service --cluster authentik-dev --service authentik-dev --desired-count 1
```

### Post-Setup Security Best Practices

After creating the initial admin user:

1. **Login** at https://dev-auth.testimonialtree.com/
2. **Create a personal admin account**:
   - Navigate to **Directory > Users > Create**
   - Use your personal email address
   - Set a strong password
3. **Add your account to the admin group**:
   - Navigate to **Directory > Groups**
   - Click on **authentik Admins**
   - Add your personal user to the group
4. **Consider deactivating akadmin**:
   - Navigate to **Directory > Users**
   - Click on **akadmin**
   - Uncheck **Is active** to disable the account
   - This prevents any logins with the default admin username

## Next Steps

After deployment and admin setup:
1. Access Authentik at `https://dev-auth.testimonialtree.com`
2. Configure initial authentication providers
3. Set up integration with your applications
4. Configure backup and monitoring as needed
