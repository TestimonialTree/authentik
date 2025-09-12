#!/bin/bash
# Run database migrations for Authentik on AWS RDS
set -e

# Configuration
ECR_REPOSITORY=${ECR_REPOSITORY:-authentik-dev}
IMAGE_TAG=${IMAGE_TAG:-latest}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-"your-account-id"}
AWS_REGION=${AWS_REGION:-us-east-1}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Running Authentik database migrations...${NC}"

# Get current directory (should be project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$PROJECT_ROOT"

# Check if .env.dev file exists
if [ ! -f ".env.dev" ]; then
    echo -e "${RED}Error: .env.dev file not found. Please configure your environment variables.${NC}"
    exit 1
fi

# Load environment variables
source .env.dev

# Check if required environment variables are set
if [ -z "$PG_HOST" ] || [ "$PG_HOST" = "your-rds-endpoint.region.rds.amazonaws.com" ]; then
    echo -e "${RED}Error: Please configure PG_HOST in .env.dev with your actual RDS endpoint${NC}"
    exit 1
fi

# Full ECR URI
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY"

# Test database connection first
echo -e "${YELLOW}Testing database connection...${NC}"
docker run --rm --env-file .env.dev \
    --entrypoint="" \
    $ECR_URI:$IMAGE_TAG \
    python -c "
import os
import psycopg2
try:
    conn = psycopg2.connect(
        host=os.environ['PG_HOST'],
        port=os.environ['PG_PORT'],
        database=os.environ['PG_DB'],
        user=os.environ['PG_USER'],
        password=os.environ['PG_PASS']
    )
    print('✅ Database connection successful')
    conn.close()
except Exception as e:
    print(f'❌ Database connection failed: {e}')
    exit(1)
"

if [ $? -ne 0 ]; then
    echo -e "${RED}Database connection failed. Please check your RDS configuration.${NC}"
    exit 1
fi

# Run migrations
echo -e "${YELLOW}Running database migrations...${NC}"
docker run --rm --env-file .env.dev \
    $ECR_URI:$IMAGE_TAG \
    ak migrate

echo -e "${GREEN}Database migrations completed successfully!${NC}"

# Create initial admin user (optional)
read -p "Do you want to create an initial admin user? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Creating initial admin user...${NC}"
    echo "Please follow the prompts to create an admin user:"
    
    docker run --rm -it --env-file .env.dev \
        $ECR_URI:$IMAGE_TAG \
        ak create_admin_group
        
    docker run --rm -it --env-file .env.dev \
        $ECR_URI:$IMAGE_TAG \
        ak bootstrap_tasks
fi

echo -e "${GREEN}Setup completed! Your Authentik instance is ready to deploy.${NC}"