#!/bin/bash

# =============================================================================
# Authentik Production Deployment Script
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")/terraform"
ENVIRONMENT="prod"
AWS_REGION="${AWS_REGION:-us-east-1}"
# Production account profile for TestimonialTree v2 (517121893353)
export AWS_PROFILE="${AWS_PROFILE:-AdministratorAccess-517121893353}"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if required tools are installed
    command -v terraform >/dev/null 2>&1 || { log_error "terraform is required but not installed. Aborting."; exit 1; }
    command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required but not installed. Aborting."; exit 1; }
    command -v docker >/dev/null 2>&1 || { log_error "Docker is required but not installed. Aborting."; exit 1; }

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or expired. Please run 'aws configure' or 'aws sso login'."
        exit 1
    fi

    # Check if terraform.tfvars exists
    if [[ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]]; then
        log_warning "terraform.tfvars not found. Please copy terraform.tfvars.example and customize it."
        log_info "cp $TERRAFORM_DIR/terraform.tfvars.example $TERRAFORM_DIR/terraform.tfvars"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

init_terraform() {
    log_info "Initializing Terraform..."
    cd "$TERRAFORM_DIR"

    terraform init
    terraform validate

    log_success "Terraform initialized and validated"
}

plan_deployment() {
    log_info "Planning Terraform deployment..."
    cd "$TERRAFORM_DIR"

    terraform plan -out=tfplan

    log_success "Terraform plan created"
    log_warning "Review the plan above before proceeding"
}

apply_deployment() {
    log_info "Applying Terraform deployment..."
    cd "$TERRAFORM_DIR"

    if [[ ! -f "tfplan" ]]; then
        log_error "No terraform plan found. Run with --plan first."
        exit 1
    fi

    terraform apply tfplan

    log_success "Infrastructure deployed successfully"
}

build_and_push_image() {
    log_info "Building and pushing Docker image..."

    # Get ECR repository URL from Terraform output
    cd "$TERRAFORM_DIR"
    ECR_REPO=$(terraform output -raw ecr_repository_url)

    if [[ -z "$ECR_REPO" ]]; then
        log_error "Could not get ECR repository URL from Terraform output"
        exit 1
    fi

    # Build and push image
    cd "$(dirname "$(dirname "$TERRAFORM_DIR")")"  # Go to project root

    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO"

    # Build image
    docker build -f Dockerfile.custom -t authentik-custom:latest .
    docker tag authentik-custom:latest "$ECR_REPO:latest"
    docker tag authentik-custom:latest "$ECR_REPO:prod-$(date +%Y%m%d-%H%M%S)"

    # Push image
    docker push "$ECR_REPO:latest"
    docker push "$ECR_REPO:prod-$(date +%Y%m%d-%H%M%S)"

    log_success "Docker image built and pushed successfully"
}

run_migrations() {
    log_info "Running database migrations..."

    cd "$TERRAFORM_DIR"
    ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)

    # Run migrations using ECS execute-command
    aws ecs execute-command \
        --cluster "$ECS_CLUSTER" \
        --task "$(aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "${ENVIRONMENT}-authentik-server" --query 'taskArns[0]' --output text | cut -d'/' -f3)" \
        --container "authentik-server" \
        --interactive \
        --command "python -m lifecycle.migrate"

    log_success "Database migrations completed"
}

health_check() {
    log_info "Running health checks..."

    cd "$TERRAFORM_DIR"
    APP_URL=$(terraform output -raw application_url)
    HEALTH_URL="${APP_URL}/-/health/live/"

    log_info "Testing application health at $HEALTH_URL"

    for i in {1..10}; do
        if curl -f -s "$HEALTH_URL" >/dev/null; then
            log_success "Health check passed"
            return 0
        else
            log_warning "Health check failed, attempt $i/10"
            sleep 30
        fi
    done

    log_error "Health check failed after 10 attempts"
    return 1
}

show_outputs() {
    log_info "Deployment outputs:"
    cd "$TERRAFORM_DIR"

    echo "Application URL: $(terraform output -raw application_url)"
    echo "ALB DNS Name: $(terraform output -raw alb_dns_name)"
    echo "ECR Repository: $(terraform output -raw ecr_repository_url)"
    echo "RDS Endpoint: $(terraform output -raw rds_endpoint)"
    echo "Redis Endpoint: $(terraform output -raw redis_endpoint)"
}

main() {
    case "${1:-}" in
        --plan)
            check_prerequisites
            init_terraform
            plan_deployment
            ;;
        --apply)
            check_prerequisites
            init_terraform
            apply_deployment
            ;;
        --build)
            check_prerequisites
            build_and_push_image
            ;;
        --migrate)
            check_prerequisites
            run_migrations
            ;;
        --health)
            health_check
            ;;
        --full)
            log_info "Running full deployment..."
            check_prerequisites
            init_terraform
            plan_deployment

            log_warning "About to apply changes. Continue? (y/N)"
            read -r response
            if [[ "$response" != "y" && "$response" != "Y" ]]; then
                log_info "Deployment cancelled"
                exit 0
            fi

            apply_deployment
            build_and_push_image
            sleep 60  # Wait for services to start
            run_migrations
            health_check
            show_outputs
            log_success "Full deployment completed successfully!"
            ;;
        --outputs)
            show_outputs
            ;;
        *)
            echo "Usage: $0 [--plan|--apply|--build|--migrate|--health|--full|--outputs]"
            echo ""
            echo "Options:"
            echo "  --plan      Create and show Terraform plan"
            echo "  --apply     Apply Terraform plan"
            echo "  --build     Build and push Docker image"
            echo "  --migrate   Run database migrations"
            echo "  --health    Run health checks"
            echo "  --full      Run complete deployment process"
            echo "  --outputs   Show deployment outputs"
            echo ""
            echo "Example usage:"
            echo "  $0 --plan     # Plan deployment"
            echo "  $0 --apply    # Apply deployment"
            echo "  $0 --full     # Complete deployment"
            exit 1
            ;;
    esac
}

main "$@"