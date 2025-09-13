#!/bin/bash

# Upload Source Code to S3 for CodePipeline
# This script packages the authentik source code and uploads it to S3

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "📦 Uploading Authentik Source Code for Pipeline"
echo "=============================================="

# Set AWS profile for dev environment
export AWS_PROFILE=authentik-dev

# Check if terraform has been deployed
if [ ! -f "$SCRIPT_DIR/terraform/terraform.tfstate" ]; then
    echo "❌ Error: Terraform state not found"
    echo "   Please deploy the infrastructure first using ./deploy-pipeline.sh"
    exit 1
fi

# Get the source bucket name from terraform output
cd "$SCRIPT_DIR/terraform"
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

if [ -z "$SOURCE_BUCKET" ]; then
    echo "❌ Error: Could not get source bucket name from Terraform"
    exit 1
fi

echo "📋 Source bucket: $SOURCE_BUCKET"

# Go to project root
cd "$PROJECT_ROOT"

# Create a temporary directory for packaging
TEMP_DIR=$(mktemp -d)
echo "📋 Using temp directory: $TEMP_DIR"

# Copy source files, excluding unnecessary files
echo "📦 Packaging source code..."
rsync -av \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='web/dist/' \
    --exclude='web/node_modules/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.terraform/' \
    --exclude='*.tfstate*' \
    --exclude='.DS_Store' \
    --exclude='deploy/dev/terraform/terraform.tfstate*' \
    --exclude='deploy/dev/terraform/.terraform/' \
    . "$TEMP_DIR/authentik-source/"

# Create the zip file
echo "🗜️  Creating source archive..."
cd "$TEMP_DIR"
zip -r source.zip authentik-source/

# Upload to S3
echo "☁️  Uploading to S3..."
aws s3 cp source.zip "s3://$SOURCE_BUCKET/source.zip"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Source code uploaded successfully!"
echo ""
echo "📝 Next steps:"
echo "1. Go to AWS CodePipeline console"
echo "2. Find your pipeline and click 'Release change'"
echo "3. Monitor the build progress in CodeBuild"
echo ""
echo "🔗 Useful links:"
echo "   CodePipeline: https://console.aws.amazon.com/codesuite/codepipeline/pipelines"
echo "   CodeBuild: https://console.aws.amazon.com/codesuite/codebuild/projects"