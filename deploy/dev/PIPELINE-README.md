# Authentik CI/CD Pipeline Deployment

This directory contains the infrastructure and deployment scripts for the Authentik CI/CD pipeline on AWS, following the same architecture pattern as the Keystory deployment.

## Architecture Overview

The pipeline follows this architecture:
- **GitHub** → **S3 Source Bucket** → **CodePipeline** → **CodeBuild** → **ECR** → **CodeDeploy** → **ECS Fargate**

## Components

- **CodePipeline**: Orchestrates the entire CI/CD process
- **CodeBuild**: Builds the Docker image using the existing Dockerfile
- **ECR**: Container registry for storing built images
- **CodeDeploy**: Handles blue/green deployments to ECS
- **ECS Fargate**: Runs the authentik containers
- **ALB**: Load balancer with SSL termination
- **RDS PostgreSQL**: Database backend
- **Secrets Manager**: Secure storage for sensitive configuration

## Prerequisites

1. AWS CLI configured with the `authentik-dev` profile
2. Terraform >= 1.0 installed
3. Access to the `597332957026` AWS account (tt-sandbox)
4. GitHub personal access token (for source uploads)

## Quick Start

### 1. Deploy the Infrastructure

```bash
./deploy-pipeline.sh
```

This will:
- Deploy all AWS resources using Terraform
- Create the CodePipeline, CodeBuild project, ECR repository
- Set up ECS cluster, ALB, RDS, and all supporting infrastructure

### 2. Configure GitHub Token

After deployment, update the GitHub token in AWS Secrets Manager:
1. Go to AWS Secrets Manager console
2. Find the secret (ARN shown in terraform output)
3. Update the `token` field with your GitHub personal access token

### 3. Upload Source Code

```bash
./upload-source.sh
```

This will:
- Package the authentik source code
- Upload it to the S3 source bucket
- Prepare it for the CodePipeline

### 4. Start the Pipeline

1. Go to AWS CodePipeline console
2. Find your pipeline (name shown in terraform output)
3. Click "Release change" to start the first build

## Manual Deployment Steps

If you prefer to deploy manually:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

## Pipeline Stages

### 1. Source Stage
- Pulls source code from S3 bucket
- Triggered manually or via S3 events

### 2. Build Stage
- Uses CodeBuild to build the Docker image
- Follows the existing multi-stage Dockerfile
- Pushes image to ECR
- Creates deployment artifacts (task definition, appspec)

### 3. Deploy Stage
- Uses CodeDeploy for blue/green deployment
- Updates ECS service with new task definition
- Performs health checks before switching traffic

## BuildSpec Configuration

The `buildspec.yml` file defines the build process:
- **Pre-build**: Login to ECR, set environment variables
- **Build**: Build Docker image with proper tags
- **Post-build**: Push to ECR, create deployment artifacts

Key environment variables:
- `AWS_ACCOUNT_ID`: AWS account ID
- `IMAGE_REPO_NAME`: ECR repository name
- `AWS_DEFAULT_REGION`: AWS region

## Infrastructure Details

### Networking
- Uses existing VPC and subnets
- ECS tasks run in private subnets
- ALB in public subnets

### Security
- Least privilege IAM roles
- Security groups restrict access
- All S3 buckets have encryption and public access blocked
- Secrets stored in AWS Secrets Manager

### Monitoring
- CloudWatch logs for all services
- ECS Container Insights enabled
- ALB access logs (optional)

## Configuration Files

- `terraform/codepipeline.tf`: Main pipeline infrastructure
- `terraform/ecs.tf`: ECS cluster, service, and task definition
- `terraform/alb.tf`: Load balancer configuration
- `terraform/rds.tf`: PostgreSQL database
- `terraform/secrets.tf`: Secrets Manager configuration
- `buildspec.yml`: CodeBuild build specification

## Environment Variables

The application uses these key environment variables:
- `AUTHENTIK_SECRET_KEY`: Application secret key
- `AUTHENTIK_POSTGRESQL__HOST`: Database host
- `AUTHENTIK_POSTGRESQL__PASSWORD`: Database password
- `AUTHENTIK_POSTGRESQL__USER`: Database user
- `AUTHENTIK_POSTGRESQL__NAME`: Database name
- `AUTHENTIK_REDIS__HOST`: Redis host (localhost in container)

## Troubleshooting

### Build Failures
1. Check CodeBuild logs in AWS console
2. Verify ECR permissions
3. Check Docker build context

### Deployment Failures
1. Check CodeDeploy deployment logs
2. Verify ECS task definition is valid
3. Check health check endpoints

### Application Issues
1. Check ECS task logs
2. Verify database connectivity
3. Check secrets configuration

## Scaling and Production Considerations

For production deployment:
1. Enable multi-AZ deployment
2. Configure auto-scaling
3. Set up proper monitoring and alerting
4. Implement proper backup strategies
5. Use encrypted storage
6. Configure WAF for additional security

## Cost Optimization

- Use appropriate instance sizes
- Configure lifecycle policies for ECR
- Set log retention policies
- Consider using Fargate Spot for development

## Cleanup

To destroy the infrastructure:

```bash
cd terraform/
terraform destroy
```

⚠️ **Warning**: This will delete all resources and data. Make sure to backup any important data first.