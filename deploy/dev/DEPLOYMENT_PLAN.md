# Authentik AWS Development Environment - Deployment Plan (Terraform + CI/CD)

## Overview

This plan deploys Authentik to AWS using Terraform and a CI/CD pipeline:
- External RDS PostgreSQL database
- Docker containerization
- SSL certificate for `dev-auth.testimonialtree.com` via ACM (DNS validation)
- CodePipeline/CodeBuild → ECR → ECS Fargate

## Architecture

```
Internet → Route 53 → ALB (SSL) → ECS Fargate → RDS PostgreSQL
                                      ↓
                                  CloudWatch Logs
```

## Prerequisites Checklist

- [ ] AWS CLI configured with appropriate permissions
- [ ] Terraform >= 1.0
- [ ] Docker installed locally
- [ ] Access to configure DNS for `testimonialtree.com` domain

## Phase 1: Infrastructure & Pipeline

### Step 1: Deploy with Terraform wrapper
```bash
# From repo root
./deploy/dev/deploy-pipeline.sh
```

Outputs include ALB DNS, ECS/Cluster names, Target Group ARN, ECR URL, RDS endpoint, SSL certificate ARN.

## Phase 2: Application Configuration

### Step 2: Configure environment & secrets
```bash
# Get RDS endpoint from Terraform outputs (host:port) and trim to host
cd deploy/dev/terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint | cut -d: -f1)
cd ../../..

# Update .env.dev with actual RDS endpoint if needed
sed -i '' "s/your-rds-endpoint.region.rds.amazonaws.com/$RDS_ENDPOINT/g" .env.dev

# Generate secret key if needed
AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)
sed -i '' "s/dev-change-this-to-a-secure-random-key-64-characters-long-minimum/$AUTHENTIK_SECRET_KEY/g" .env.dev

# Create/update unified JSON secret in Secrets Manager
bash deploy/dev/scripts/secrets-sync.sh
```

### Step 3: Build & deliver images
Option A — Use CodePipeline (recommended):
```bash
./deploy/dev/upload-source.sh
# Then in AWS Console: CodePipeline → Release change
```

Option B — Build/push locally for testing:
```bash
chmod +x deploy/dev/scripts/*.sh
./deploy/dev/scripts/build-and-push.sh
```

## Phase 3: Database Setup

### Step 4: Initialize database schema
```bash
./deploy/dev/scripts/run-migrations.sh

# This will:
# - Test database connectivity
# - Run Authentik migrations
```

## Phase 4: Service Deployment

### Step 5: Deploy to ECS
```bash
# Preferred: let CodePipeline deploy to ECS

# Optional: manual emergency deploy to ECS Fargate
./deploy/dev/scripts/manual-deploy.sh
```

## Phase 5: DNS and SSL Configuration

### Step 6: Validate ACM certificate & configure DNS
- Complete DNS validation for the ACM certificate (see Terraform output `ssl_certificate_arn` and ACM console).
- Create an A record `dev-auth.testimonialtree.com` → ALB DNS from Terraform output `load_balancer_dns`.

### Step 7: Test Deployment
```bash
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

## File Structure

```
deploy/dev/
├── DEPLOYMENT_PLAN.md             # This file
├── README.md                      # Detailed deployment guide
├── PIPELINE-README.md             # CI/CD details
├── SSL_SETUP.md                   # SSL configuration options
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
# Terraform outputs
cd deploy/dev/terraform && terraform output && cd ../../..

# View ECS service status
aws ecs describe-services --cluster authentik-dev --services authentik-dev

# Check target group health
aws elbv2 describe-target-health --target-group-arn $(cd deploy/dev/terraform && terraform output -raw target_group_arn)

# View application logs
aws logs tail /ecs/authentik-dev --follow
```

## Cleanup Instructions

To remove all resources:
```bash
cd deploy/dev/terraform
terraform destroy

# Optional: clean up ECR images
aws ecr batch-delete-image \
  --repository-name authentik-dev \
  --image-ids imageTag=latest
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

This plan provides a complete, production-ready development environment for Authentik on AWS with external PostgreSQL database and SSL termination, using Terraform and a CI/CD pipeline.
