# Authentik Production Deployment

Complete production deployment for Authentik with AWS ECS Fargate, RDS PostgreSQL, and ElastiCache Redis.

## 🏗️ Architecture Overview

### Baseline Production Setup
- **Compute**: ECS Fargate (2 server tasks + 1 worker task)
- **Database**: RDS PostgreSQL 15 (db.t3.small, Multi-AZ)
- **Cache**: ElastiCache Redis 7.0 (cache.t3.micro)
- **Load Balancer**: Application Load Balancer with SSL
- **Storage**: S3 for media files
- **Monitoring**: CloudWatch logs, metrics, and alarms
- **Security**: VPC, Security Groups, KMS encryption, Secrets Manager

### Monthly Cost Estimate
**~$150-160/month** for baseline production setup

## 📋 Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Docker](https://www.docker.com/get-started) >= 20.0
- Valid AWS account with appropriate permissions

### Required AWS Resources
- **Domain name** registered and managed in Route 53 (or DNS configured elsewhere)
- **SSL certificate** issued via AWS Certificate Manager
- **S3 bucket** for Terraform state (recommended)

### AWS Permissions Required
- EC2, VPC, ECS, RDS, ElastiCache
- IAM role and policy management
- Secrets Manager, KMS
- CloudWatch, SNS
- S3, ECR

## 🚀 Quick Start

### 1. Configure Environment
```bash
# Clone and navigate to production deployment
cd deploy/prod/terraform

# Copy and customize configuration
cp terraform.tfvars.example terraform.tfvars
```

### 2. Update Configuration
Edit `terraform.tfvars` with your values:
```hcl
# Domain and SSL
domain_name     = "auth.yourdomain.com"
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."

# Security
authentik_secret_key = "your-very-secure-secret-key-here"
notification_email   = "admin@yourdomain.com"

# Optional: Restrict access
allowed_cidr_blocks = ["YOUR_OFFICE_IP/32"]
```

### 3. Deploy Infrastructure
```bash
# Initialize and plan
./scripts/deploy.sh --plan

# Review the plan, then apply
./scripts/deploy.sh --apply

# Build and deploy application
./scripts/deploy.sh --build

# Run database migrations
./scripts/deploy.sh --migrate

# Verify deployment
./scripts/deploy.sh --health
```

### 4. Complete Setup
```bash
# View deployment outputs
./scripts/deploy.sh --outputs

# Configure DNS to point to ALB
# Create first admin user via web interface
```

## 📁 Directory Structure

```
deploy/prod/
├── terraform/                 # Infrastructure as Code
│   ├── main.tf                 # Core infrastructure
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Output values
│   ├── ecs.tf                  # ECS cluster and services
│   ├── rds.tf                  # PostgreSQL database
│   ├── elasticache.tf          # Redis cache
│   ├── alb.tf                  # Load balancer
│   ├── security.tf             # Security groups and IAM
│   ├── monitoring.tf           # CloudWatch setup
│   ├── terraform.tfvars.example # Configuration template
│   └── upgrades/               # Future upgrade modules
├── scripts/                    # Deployment automation
│   ├── deploy.sh               # Main deployment script
│   └── rollback.sh             # Rollback and recovery
├── buildspec.yml              # CodeBuild configuration
├── README.md                  # This file
└── UPGRADE_PLAN.md           # Scaling and enhancement guide
```

## 🔧 Deployment Scripts

### Deploy Script
```bash
./scripts/deploy.sh --help

# Available commands:
--plan      # Create and show Terraform plan
--apply     # Apply Terraform plan
--build     # Build and push Docker image
--migrate   # Run database migrations
--health    # Run health checks
--full      # Complete deployment process
--outputs   # Show deployment outputs
```

### Rollback Script
```bash
./scripts/rollback.sh --help

# Available commands:
--list-images               # List available Docker images
--rollback-image <tag>      # Rollback to specific image
--status                    # Show current deployment status
--health                    # Check application health
--emergency-down            # Scale services to 0 (emergency)
--emergency-up              # Scale services back up
```

## 🔐 Security Configuration

### Network Security
- **VPC**: Isolated network with public/private subnets
- **Security Groups**: Least-privilege access rules
- **NAT Gateways**: Secure internet access for private subnets

### Data Security
- **Encryption at Rest**: KMS encryption for RDS, Redis, S3, and logs
- **Encryption in Transit**: SSL/TLS for all connections
- **Secrets Management**: AWS Secrets Manager for credentials

### Access Control
- **IAM Roles**: Service-specific roles with minimal permissions
- **Allowed CIDR Blocks**: Configurable IP restrictions
- **SSL Certificate**: HTTPS-only access via ACM

## 📊 Monitoring and Alerting

### CloudWatch Dashboard
- Application Load Balancer metrics
- ECS service performance
- RDS database metrics
- Redis cache metrics
- Application logs

### Automated Alerts
- High CPU/memory utilization
- Failed health checks
- Database connection issues
- Application errors
- Failed login attempts

### Log Management
- Centralized logging via CloudWatch
- 14-day retention (configurable)
- Structured log analysis queries
- Error and performance monitoring

## 🆙 Scaling and Upgrades

This deployment is designed for progressive enhancement. See [UPGRADE_PLAN.md](UPGRADE_PLAN.md) for detailed upgrade options:

### Option A: High Availability (+$100-120/month)
- Auto-scaling (2-4 ECS tasks)
- CloudFront CDN
- WAF protection
- RDS read replica
- Redis cluster mode

### Option B: Enterprise-Grade (+$250-320/month)
- Multi-region deployment
- Enhanced security features
- Advanced monitoring and tracing
- Automated backup and recovery

## 🚨 Disaster Recovery

### Backup Strategy
- **RDS**: Automated daily backups (7-day retention)
- **Redis**: Daily snapshots
- **Application Code**: ECR image versioning
- **Infrastructure**: Terraform state backups

### Recovery Procedures
1. **Database Recovery**: Restore from automated backup or snapshot
2. **Application Recovery**: Deploy previous Docker image version
3. **Infrastructure Recovery**: Re-apply Terraform configuration
4. **DNS Failover**: Update Route 53 records if needed

## 🛠️ Maintenance

### Regular Tasks
- **Monthly**: Review CloudWatch metrics and costs
- **Quarterly**: Update base Docker image versions
- **Bi-annually**: Review and rotate secrets
- **As needed**: Apply security patches and updates

### Update Procedures
1. **Application Updates**: Build new image, deploy via ECS
2. **Infrastructure Updates**: Update Terraform, plan, and apply
3. **Database Updates**: Use RDS maintenance windows
4. **Security Updates**: Regular credential rotation

## 🔍 Troubleshooting

### Common Issues

#### Service Not Starting
```bash
# Check ECS service status
aws ecs describe-services --cluster prod-authentik --services prod-authentik-server

# Check task logs
aws logs tail /ecs/prod-authentik --follow
```

#### Database Connection Issues
```bash
# Verify security groups allow ECS -> RDS
# Check RDS instance status
aws rds describe-db-instances --db-instance-identifier prod-authentik-postgres
```

#### Health Check Failures
```bash
# Test application health endpoint
curl -f https://auth.yourdomain.com/-/health/live/

# Check ALB target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

### Emergency Procedures
1. **Scale down**: Use rollback script to reduce costs
2. **Emergency stop**: Scale services to 0 tasks
3. **Quick recovery**: Deploy previous known-good version
4. **Database issues**: Switch to read replica if available

## 💰 Cost Optimization

### Immediate Savings
- Use smaller instance types for development
- Enable `enable_nat_instance = true` for cost savings
- Adjust CloudWatch log retention periods
- Use Reserved Instances for long-term deployments

### Monitoring Costs
- Set up AWS billing alerts
- Use AWS Cost Explorer for analysis
- Monitor data transfer costs
- Review and optimize resource utilization

## 📞 Support

### Documentation
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Authentik Documentation](https://goauthentik.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Monitoring
- CloudWatch Dashboard: `https://console.aws.amazon.com/cloudwatch/`
- Application Health: `https://auth.yourdomain.com/-/health/live/`
- ECS Console: Monitor services and tasks

### Emergency Contacts
- Configure SNS notifications for critical alerts
- Set up PagerDuty or similar for 24/7 monitoring
- Document escalation procedures

---

## ✅ Post-Deployment Checklist

- [ ] DNS configured and resolving correctly
- [ ] SSL certificate valid and trusted
- [ ] Application accessible at configured domain
- [ ] Admin user created and can log in
- [ ] Health checks passing
- [ ] CloudWatch alarms configured
- [ ] Backup procedures tested
- [ ] Security scan completed
- [ ] Documentation updated
- [ ] Team trained on deployment procedures

---

**Ready to deploy?** Start with `./scripts/deploy.sh --plan` and follow the quick start guide above!