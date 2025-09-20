#!/bin/bash

# =============================================================================
# Authentik Production Rollback Script
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

get_ecs_info() {
    cd "$TERRAFORM_DIR"
    ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)
    ECS_SERVER_SERVICE="${ENVIRONMENT}-authentik-server"
    ECS_WORKER_SERVICE="${ENVIRONMENT}-authentik-worker"
    ECR_REPO=$(terraform output -raw ecr_repository_url)
}

list_available_images() {
    log_info "Available images for rollback:"

    aws ecr describe-images \
        --repository-name "${ENVIRONMENT}-authentik" \
        --query 'imageDetails[?imageTagStatus==`TAGGED`].[imageTags[0],imagePushedAt]' \
        --output table \
        --region "$AWS_REGION" | head -20

    echo ""
}

get_current_task_definition() {
    local service_name="$1"

    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "$service_name" \
        --query 'services[0].taskDefinition' \
        --output text \
        --region "$AWS_REGION"
}

get_previous_task_definitions() {
    local family="$1"

    log_info "Previous task definitions for $family:"
    aws ecs list-task-definitions \
        --family-prefix "$family" \
        --status ACTIVE \
        --sort DESC \
        --query 'taskDefinitionArns[0:5]' \
        --output table \
        --region "$AWS_REGION"
}

rollback_to_image() {
    local image_tag="$1"

    if [[ -z "$image_tag" ]]; then
        log_error "Image tag is required"
        exit 1
    fi

    log_warning "This will rollback both server and worker services to image: $ECR_REPO:$image_tag"
    log_warning "Current services will be updated immediately. Continue? (y/N)"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi

    # Update both services to use the specified image
    log_info "Rolling back server service..."
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_SERVER_SERVICE" \
        --task-definition "$ECS_SERVER_SERVICE" \
        --force-new-deployment \
        --region "$AWS_REGION"

    log_info "Rolling back worker service..."
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_WORKER_SERVICE" \
        --task-definition "$ECS_WORKER_SERVICE" \
        --force-new-deployment \
        --region "$AWS_REGION"

    # Wait for deployment to stabilize
    log_info "Waiting for services to stabilize..."
    aws ecs wait services-stable \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVER_SERVICE" "$ECS_WORKER_SERVICE" \
        --region "$AWS_REGION"

    log_success "Rollback completed successfully"
}

rollback_to_task_definition() {
    local task_def_arn="$1"
    local service_name="$2"

    if [[ -z "$task_def_arn" || -z "$service_name" ]]; then
        log_error "Task definition ARN and service name are required"
        exit 1
    fi

    log_warning "This will rollback $service_name to task definition: $task_def_arn"
    log_warning "Continue? (y/N)"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi

    log_info "Rolling back $service_name..."
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$service_name" \
        --task-definition "$task_def_arn" \
        --region "$AWS_REGION"

    # Wait for deployment to stabilize
    log_info "Waiting for service to stabilize..."
    aws ecs wait services-stable \
        --cluster "$ECS_CLUSTER" \
        --services "$service_name" \
        --region "$AWS_REGION"

    log_success "Service $service_name rolled back successfully"
}

emergency_scale_down() {
    log_warning "EMERGENCY: Scaling down all services to 0 tasks"
    log_warning "This will cause downtime. Continue? (y/N)"
    read -r response
    if [[ "$response" != "y" && "$response" != "Y" ]]; then
        log_info "Emergency scale-down cancelled"
        exit 0
    fi

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_SERVER_SERVICE" \
        --desired-count 0 \
        --region "$AWS_REGION"

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_WORKER_SERVICE" \
        --desired-count 0 \
        --region "$AWS_REGION"

    log_success "Services scaled down to 0"
}

emergency_scale_up() {
    log_info "Scaling services back up to normal capacity"

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_SERVER_SERVICE" \
        --desired-count 2 \
        --region "$AWS_REGION"

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$ECS_WORKER_SERVICE" \
        --desired-count 1 \
        --region "$AWS_REGION"

    log_success "Services scaled back up"
}

check_health() {
    cd "$TERRAFORM_DIR"
    APP_URL=$(terraform output -raw application_url)
    HEALTH_URL="${APP_URL}/-/health/live/"

    log_info "Checking application health at $HEALTH_URL"

    if curl -f -s "$HEALTH_URL" >/dev/null; then
        log_success "Application is healthy"
        return 0
    else
        log_error "Application health check failed"
        return 1
    fi
}

show_current_status() {
    log_info "Current deployment status:"

    echo "Server Service:"
    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVER_SERVICE" \
        --query 'services[0].{TaskDefinition:taskDefinition,RunningCount:runningCount,DesiredCount:desiredCount,Status:status}' \
        --output table \
        --region "$AWS_REGION"

    echo ""
    echo "Worker Service:"
    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_WORKER_SERVICE" \
        --query 'services[0].{TaskDefinition:taskDefinition,RunningCount:runningCount,DesiredCount:desiredCount,Status:status}' \
        --output table \
        --region "$AWS_REGION"

    echo ""
    check_health
}

main() {
    # Check prerequisites
    command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required but not installed. Aborting."; exit 1; }
    command -v terraform >/dev/null 2>&1 || { log_error "terraform is required but not installed. Aborting."; exit 1; }

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or expired."
        exit 1
    fi

    get_ecs_info

    case "${1:-}" in
        --list-images)
            list_available_images
            ;;
        --list-tasks)
            get_previous_task_definitions "${ENVIRONMENT}-authentik-server"
            echo ""
            get_previous_task_definitions "${ENVIRONMENT}-authentik-worker"
            ;;
        --rollback-image)
            if [[ -z "${2:-}" ]]; then
                log_error "Image tag is required. Usage: $0 --rollback-image <tag>"
                exit 1
            fi
            rollback_to_image "$2"
            ;;
        --rollback-task)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                log_error "Task definition ARN and service name are required."
                log_error "Usage: $0 --rollback-task <task-def-arn> <service-name>"
                exit 1
            fi
            rollback_to_task_definition "$2" "$3"
            ;;
        --emergency-down)
            emergency_scale_down
            ;;
        --emergency-up)
            emergency_scale_up
            ;;
        --status)
            show_current_status
            ;;
        --health)
            check_health
            ;;
        *)
            echo "Authentik Production Rollback Script"
            echo ""
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  --list-images                List available Docker images"
            echo "  --list-tasks                 List previous task definitions"
            echo "  --rollback-image <tag>       Rollback to specific Docker image tag"
            echo "  --rollback-task <arn> <svc>  Rollback to specific task definition"
            echo "  --emergency-down             Scale all services to 0 (emergency)"
            echo "  --emergency-up               Scale services back to normal"
            echo "  --status                     Show current deployment status"
            echo "  --health                     Check application health"
            echo ""
            echo "Examples:"
            echo "  $0 --list-images"
            echo "  $0 --rollback-image prod-20241201-143022"
            echo "  $0 --status"
            echo "  $0 --health"
            exit 1
            ;;
    esac
}

main "$@"