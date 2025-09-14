# Authentik AWS Development Environment - Deployment Plan

## Overview

This plan outlines the complete deployment of Authentik to AWS with:
- External RDS PostgreSQL database
- Docker containerization 
- SSL certificate for `dev-auth.testimonialtree.com`
- Complete AWS infrastructure automation

## Architecture

```
Internet → Route 53 → ALB (SSL) → ECS Fargate → RDS PostgreSQL
                                      ↓
                                  CloudWatch Logs
```

## Prerequisites Checklist

- [ ] AWS CLI configured with appropriate permissions
- [ ] Docker installed locally
- [ ] AWS Account ID available
- [ ] Access to configure DNS for `testimonialtree.com` domain
- [ ] Route 53 Hosted Zone ID (optional but recommended)

## Phase 1: Infrastructure Deployment

### Step 1: Set Environment Variables
```bash
export AWS_REGION=us-west-2
export AWS_ACCOUNT_ID=your-account-id
export HOSTED_ZONE_ID=your-route53-hosted-zone-id  # optional
```

### Step 2: Deploy AWS Infrastructure
```bash
# Deploy complete infrastructure using CloudFormation
aws cloudformation create-stack \
  --stack-name authentik-dev-infrastructure \
  --template-body file://deploy/dev/aws-infrastructure.yml \
  --parameters ParameterKey=DomainName,ParameterValue=dev-auth.testimonialtree.com \
               ParameterKey=HostedZoneId,ParameterValue=$HOSTED_ZONE_ID \
  --capabilities CAPABILITY_IAM \
  --region $AWS_REGION

# Wait for completion (10-15 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name authentik-dev-infrastructure \
  --region $AWS_REGION
```

**What this creates:**
- VPC with public/private subnets
- RDS PostgreSQL instance (db.t3.micro)
- ECS Fargate cluster
- Application Load Balancer with SSL
- Route 53 DNS record
- Security groups and IAM roles
- Secrets Manager for credentials
- ECR repository

## Phase 2: Application Configuration

### Step 3: Configure Environment Variables
```bash
# Get RDS endpoint from CloudFormation outputs
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name authentik-dev-infrastructure \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
  --output text \
  --region $AWS_REGION)

# Update .env.dev with actual RDS endpoint
sed -i "s/your-rds-endpoint.region.rds.amazonaws.com/$RDS_ENDPOINT/g" .env.dev

# Generate secure secret key
AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)
sed -i "s/dev-change-this-to-a-secure-random-key-64-characters-long-minimum/$AUTHENTIK_SECRET_KEY/g" .env.dev
```

### Step 4: Build and Push Docker Image
```bash
# Make scripts executable
chmod +x deploy/dev/scripts/*.sh

# Build and push to ECR
./deploy/dev/scripts/build-and-push.sh
```

## Phase 3: Database Setup

### Step 5: Initialize Database Schema
```bash
# Run database migrations and setup
./deploy/dev/scripts/run-migrations.sh

# This will:
# - Test database connectivity
# - Run Authentik migrations
# - Optionally create admin user
```

## Phase 4: Service Deployment

### Step 6: Deploy to ECS
```bash
# Recommended: use CodePipeline to deploy (commit triggers build/deploy)

# Optional: manual emergency deploy to ECS Fargate
./deploy/dev/scripts/manual-deploy.sh

# This creates:
# - ECS task definition
# - Service configuration
# - Target group registration
```

## Phase 5: DNS and SSL Configuration

### Step 7: Verify SSL Certificate
The CloudFormation template automatically:
- Requests SSL certificate from ACM
- Validates via DNS (if Route 53 hosted zone provided)
- Configures ALB listeners for HTTP→HTTPS redirect

### Step 8: Test Deployment
```bash
# Check certificate validation
aws acm describe-certificate \
  --certificate-arn $(aws cloudformation describe-stacks \
    --stack-name authentik-dev-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`SSLCertificate`].OutputValue' \
    --output text)

# Test connectivity
curl -I https://dev-auth.testimonialtree.com/-/health/ready/
```

## Verification Steps

### Health Checks
- [ ] RDS instance is running and accessible
- [ ] ECS tasks are healthy
- [ ] ALB target groups show healthy targets
- [ ] SSL certificate is validated and active
- [ ] DNS resolution works for `dev-auth.testimonialtree.com`
- [ ] Application responds at HTTPS endpoint

### Monitoring Setup
- [ ] CloudWatch logs are collecting container logs
- [ ] ECS service auto-scaling is configured
- [ ] ALB health checks are passing
- [ ] RDS monitoring is enabled

## File Structure Created

```
deploy/dev/
├── DEPLOYMENT_PLAN.md             # This file
├── README.md                      # Detailed deployment guide
├── SSL_SETUP.md                   # SSL configuration options
├── aws-infrastructure.yml         # CloudFormation template
├── docker-compose.dev.yml         # Local testing compose
└── scripts/
    ├── build-and-push.sh         # ECR image build/push
    ├── run-migrations.sh         # Database initialization
    └── manual-deploy.sh          # Manual ECS service deployment
```

## Environment Variables Reference

Key variables in `.env.dev`:
```bash
# Database (RDS)
PG_HOST=your-rds-endpoint.region.rds.amazonaws.com
PG_PASS=your-secure-rds-password
PG_USER=authentik
PG_DB=authentik_dev

# Domain & SSL
AUTHENTIK_COOKIE_DOMAIN=dev-auth.testimonialtree.com
AUTHENTIK_CSRF_COOKIE_SECURE=true
AUTHENTIK_SESSION_COOKIE_SECURE=true

# Security
AUTHENTIK_SECRET_KEY=your-64-character-secret-key
```

## Cost Estimate (Development)

Monthly costs (approximate):
- RDS db.t3.micro: $15-20
- ALB: $20-25
- ECS Fargate: $10-15 (minimal resources)
- Route 53: $0.50
- **Total: ~$50-60/month**

## Troubleshooting

### Common Issues
1. **SSL Certificate not validating**: Check DNS records and Route 53 configuration
2. **ECS tasks failing**: Check CloudWatch logs in `/ecs/authentik-dev`
3. **Database connection issues**: Verify security group rules and RDS endpoint
4. **ALB health checks failing**: Confirm target group configuration and container health

### Debug Commands
```bash
# Check CloudFormation stack status
aws cloudformation describe-stacks --stack-name authentik-dev-infrastructure

# View ECS service status
aws ecs describe-services --cluster authentik-dev --services authentik-dev-service

# Check target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# View application logs
aws logs tail /ecs/authentik-dev --follow
```

## Cleanup Instructions

To remove all resources:
```bash
# Delete CloudFormation stack (removes most resources)
aws cloudformation delete-stack \
  --stack-name authentik-dev-infrastructure \
  --region $AWS_REGION

# Clean up ECR images
aws ecr batch-delete-image \
  --repository-name authentik-dev \
  --image-ids imageTag=latest \
  --region $AWS_REGION
```

## Next Steps After Deployment

1. Access Authentik admin interface at `https://dev-auth.testimonialtree.com`
2. Configure authentication providers (OIDC, SAML, etc.)
3. Set up application integrations
4. Configure user provisioning and groups
5. Implement backup and disaster recovery procedures

## Security Notes

- All database credentials stored in AWS Secrets Manager
- Network traffic encrypted in transit (SSL/TLS)
- RDS instance isolated in private subnets
- Security groups follow least-privilege principles
- Container logs sanitized of sensitive information

---

**Status: Ready for Execution**

This plan provides a complete, production-ready development environment for Authentik on AWS with external PostgreSQL database and SSL termination.
