#!/bin/bash
# Deploy Authentik to AWS ECS Fargate (development environment)
set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME=${CLUSTER_NAME:-authentik-dev}
SERVICE_NAME=${SERVICE_NAME:-authentik-dev-service}
ECR_REPOSITORY=${ECR_REPOSITORY:-authentik-dev}
IMAGE_TAG=${IMAGE_TAG:-latest}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-"your-account-id"}
DOMAIN_NAME=${DOMAIN_NAME:-dev-auth.testimonialtree.com}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Deploying Authentik to ECS Fargate...${NC}"

# Get current directory (should be project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$PROJECT_ROOT"

# Check if required environment variables are set
if [ "$AWS_ACCOUNT_ID" = "your-account-id" ]; then
    echo -e "${RED}Error: Please set AWS_ACCOUNT_ID environment variable${NC}"
    exit 1
fi

# Full ECR URI
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY"

# Create ECS cluster if it doesn't exist
echo -e "${YELLOW}Ensuring ECS cluster exists...${NC}"
aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION 2>/dev/null || {
    echo -e "${YELLOW}Creating ECS cluster: $CLUSTER_NAME${NC}"
    aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION
}

# Create task definition
echo -e "${YELLOW}Creating/updating task definition...${NC}"
cat > deploy/dev/task-definition.json << EOF
{
  "family": "authentik-dev",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/authentik-dev-ecs-execution-role",
  "containerDefinitions": [
    {
      "name": "authentik-server",
      "image": "$ECR_URI:$IMAGE_TAG",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 9000,
          "protocol": "tcp"
        },
        {
          "containerPort": 9443,
          "protocol": "tcp"
        }
      ],
      "command": ["server"],
      "environment": [
        {
          "name": "AUTHENTIK_COOKIE_DOMAIN",
          "value": "$DOMAIN_NAME"
        },
        {
          "name": "AUTHENTIK_CSRF_COOKIE_SECURE",
          "value": "true"
        },
        {
          "name": "AUTHENTIK_SESSION_COOKIE_SECURE",
          "value": "true"
        }
      ],
      "secrets": [
        {
          "name": "AUTHENTIK_SECRET_KEY",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/secret-key"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__HOST",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-host"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-password"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__USER",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-user"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__NAME",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-database"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/authentik-dev",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "python -c \"import requests; requests.get('http://localhost:9000/-/health/ready/')\""
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    },
    {
      "name": "authentik-worker",
      "image": "$ECR_URI:$IMAGE_TAG",
      "essential": true,
      "command": ["worker"],
      "secrets": [
        {
          "name": "AUTHENTIK_SECRET_KEY",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/secret-key"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__HOST",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-host"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-password"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__USER",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-user"
        },
        {
          "name": "AUTHENTIK_POSTGRESQL__NAME",
          "valueFrom": "arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:authentik-dev/rds-database"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/authentik-dev",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    },
    {
      "name": "redis",
      "image": "docker.io/library/redis:alpine",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 6379,
          "protocol": "tcp"
        }
      ],
      "command": ["redis-server", "--save", "60", "1", "--loglevel", "warning"],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/authentik-dev",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

# Register task definition
echo -e "${YELLOW}Registering task definition...${NC}"
aws ecs register-task-definition \
    --cli-input-json file://deploy/dev/task-definition.json \
    --region $AWS_REGION

echo -e "${GREEN}ECS task definition created successfully!${NC}"
echo -e "${YELLOW}Note: You'll need to:${NC}"
echo "1. Create AWS Secrets Manager secrets for database credentials"
echo "2. Create VPC, subnets, and security groups"
echo "3. Create Application Load Balancer with SSL certificate"
echo "4. Create ECS service with the task definition"
echo "5. Configure Route 53 DNS record"
echo ""
echo -e "${YELLOW}See deploy/dev/aws-infrastructure.yml for CloudFormation template${NC}"