#!/bin/bash
# Build and push Authentik development Docker image to ECR
set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REPOSITORY=${ECR_REPOSITORY:-authentik-dev}
IMAGE_TAG=${IMAGE_TAG:-latest}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-"your-account-id"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building and pushing Authentik development image...${NC}"

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

echo -e "${YELLOW}ECR URI: $ECR_URI:$IMAGE_TAG${NC}"

# Login to ECR
echo -e "${YELLOW}Logging into ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Create ECR repository if it doesn't exist
echo -e "${YELLOW}Ensuring ECR repository exists...${NC}"
aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION 2>/dev/null || {
    echo -e "${YELLOW}Creating ECR repository: $ECR_REPOSITORY${NC}"
    aws ecr create-repository --repository-name $ECR_REPOSITORY --region $AWS_REGION
}

# Build the image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -f Dockerfile.dev -t $ECR_URI:$IMAGE_TAG .

# Tag with additional tags if needed
docker tag $ECR_URI:$IMAGE_TAG $ECR_URI:dev-$(date +%Y%m%d-%H%M%S)

# Push the image
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:dev-$(date +%Y%m%d-%H%M%S)

echo -e "${GREEN}Successfully built and pushed image: $ECR_URI:$IMAGE_TAG${NC}"
echo -e "${GREEN}Also tagged with timestamp: $ECR_URI:dev-$(date +%Y%m%d-%H%M%S)${NC}"

# Output the image URI for use in deployment
echo "IMAGE_URI=$ECR_URI:$IMAGE_TAG" > deploy/dev/.env.image