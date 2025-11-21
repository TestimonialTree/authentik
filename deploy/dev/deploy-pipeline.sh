#!/bin/bash

# Deploy Authentik CI/CD Pipeline
# This script deploys the complete infrastructure for the Authentik CodePipeline

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

echo "🚀 Deploying Authentik CI/CD Pipeline"
echo "======================================"

# Check if we're in the right AWS account
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
EXPECTED_ACCOUNT="597332957026"

if [ "$AWS_ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
    echo "❌ Error: You're in the wrong AWS account"
    echo "   Current: $AWS_ACCOUNT"
    echo "   Expected: $EXPECTED_ACCOUNT (tt-sandbox)"
    echo "   Please switch to the correct AWS profile: aws configure set profile authentik-dev"
    exit 1
fi

echo "✅ Confirmed AWS account: $AWS_ACCOUNT (tt-sandbox)"

# Set AWS profile for dev environment
export AWS_PROFILE=authentik-dev

# Navigate to terraform directory
cd "$TERRAFORM_DIR"

echo ""
echo "📋 Initializing Terraform..."
terraform init

echo ""
echo "📋 Planning Terraform deployment..."
terraform plan -out=tfplan

echo ""
echo "🚀 Applying Terraform configuration..."
terraform apply tfplan

echo ""
echo "📋 Getting outputs..."
terraform output

echo ""
echo "✅ Pipeline deployment complete!"
echo ""
echo "📝 Next steps:"
echo "1. Update the GitHub token in AWS Secrets Manager:"
echo "   - Go to AWS Secrets Manager console"
echo "   - Find the secret: $(terraform output -raw github_secret_arn | cut -d: -f6)"
echo "   - Update the 'token' value with your GitHub personal access token"
echo ""
echo "2. Upload your source code to the S3 bucket:"
echo "   - Bucket: $(terraform output -raw source_bucket_name)"
echo "   - Upload a zip file named 'source.zip' containing your code"
echo ""
echo "3. Start the pipeline:"
echo "   - Go to AWS CodePipeline console"
echo "   - Find pipeline: $(terraform output -raw codepipeline_name)"
echo "   - Click 'Release change' to start the first build"
echo ""
echo "🌐 Your application will be available at:"
echo "   https://dev-auth.testimonialtree.com"