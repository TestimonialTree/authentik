#!/bin/bash
# Create initial admin user for Authentik on AWS ECS
set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME=${CLUSTER_NAME:-authentik-dev}
SERVICE_NAME=${SERVICE_NAME:-authentik-dev}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

print_success() {
    echo -e "${GREEN}Success:${NC} $1"
}

echo -e "${YELLOW}Authentik Initial Admin User Setup${NC}"
echo "======================================="
echo

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    print_error "AWS CLI not configured or no valid credentials found"
    echo "Please run: aws configure"
    exit 1
fi

# Check if the service exists
print_step "Checking ECS service status..."
SERVICE_STATUS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --query 'services[0].status' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "NOT_FOUND")

if [ "$SERVICE_STATUS" = "NOT_FOUND" ] || [ "$SERVICE_STATUS" = "None" ]; then
    print_error "ECS service '$SERVICE_NAME' not found in cluster '$CLUSTER_NAME'"
    exit 1
fi

# Get service configuration
print_step "Getting service configuration..."
SERVICE_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --query 'services[0]' \
    --region "$AWS_REGION")

TASK_DEFINITION_ARN=$(echo "$SERVICE_INFO" | jq -r '.taskDefinition')
NETWORK_CONFIG=$(echo "$SERVICE_INFO" | jq -r '.networkConfiguration')
SUBNETS=$(echo "$NETWORK_CONFIG" | jq -r '.awsvpcConfiguration.subnets | join(",")')
SECURITY_GROUPS=$(echo "$NETWORK_CONFIG" | jq -r '.awsvpcConfiguration.securityGroups | join(",")')

echo "  Task Definition: $TASK_DEFINITION_ARN"
echo "  Subnets: $SUBNETS"
echo "  Security Groups: $SECURITY_GROUPS"

# Ask user for confirmation before proceeding
echo
print_warning "This script will temporarily scale down the service and run admin setup commands."
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Step 1: Scale down the service
print_step "Scaling down service to 0..."
aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --desired-count 0 \
    --region "$AWS_REGION" >/dev/null

echo "Waiting for service to scale down..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

print_success "Service scaled down successfully"

# Function to run ECS task and wait for completion
run_task() {
    local command_json="$1"
    local description="$2"

    print_step "$description"

    TASK_ARN=$(aws ecs run-task \
        --cluster "$CLUSTER_NAME" \
        --task-definition "$TASK_DEFINITION_ARN" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
        --overrides "$command_json" \
        --query 'tasks[0].taskArn' \
        --output text \
        --region "$AWS_REGION")

    if [ "$TASK_ARN" = "None" ] || [ -z "$TASK_ARN" ]; then
        print_error "Failed to start task"
        return 1
    fi

    echo "  Task ARN: $TASK_ARN"
    echo "  Waiting for task to complete..."

    aws ecs wait tasks-stopped \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$AWS_REGION"

    # Check exit code
    TASK_DETAILS=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0]' \
        --region "$AWS_REGION")

    EXIT_CODE=$(echo "$TASK_DETAILS" | jq -r '.containers[] | select(.name=="authentik-server") | .exitCode')

    if [ "$EXIT_CODE" = "0" ]; then
        print_success "Task completed successfully"
        return 0
    else
        print_error "Task failed with exit code: $EXIT_CODE"

        # Show logs if available
        TASK_ID=$(basename "$TASK_ARN")
        LOG_STREAM="ecs/authentik-server/$TASK_ID"

        echo "Recent logs:"
        aws logs get-log-events \
            --log-group-name "/ecs/authentik-dev" \
            --log-stream-name "$LOG_STREAM" \
            --query 'events[].message' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null | tail -10 || echo "No logs available"

        return 1
    fi
}

# Step 2: Create admin group
ADMIN_GROUP_COMMAND='{
    "containerOverrides": [
        {
            "name": "authentik-server",
            "command": ["ak", "create_admin_group"]
        },
        {
            "name": "authentik-worker",
            "command": ["sleep", "60"]
        }
    ]
}'

if ! run_task "$ADMIN_GROUP_COMMAND" "Creating admin group..."; then
    print_error "Failed to create admin group"

    # Scale service back up before exiting
    print_step "Scaling service back up..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count 1 \
        --region "$AWS_REGION" >/dev/null

    exit 1
fi

# Step 3: Bootstrap tasks
BOOTSTRAP_COMMAND='{
    "containerOverrides": [
        {
            "name": "authentik-server",
            "command": ["ak", "bootstrap_tasks"]
        },
        {
            "name": "authentik-worker",
            "command": ["sleep", "60"]
        }
    ]
}'

if ! run_task "$BOOTSTRAP_COMMAND" "Running bootstrap tasks..."; then
    print_warning "Bootstrap tasks failed, but this is sometimes normal"
fi

# Step 4: Scale service back up
print_step "Scaling service back up..."
aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --desired-count 1 \
    --region "$AWS_REGION" >/dev/null

echo "Waiting for service to be stable..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

print_success "Service scaled back up successfully"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Admin Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Next steps:"
echo "1. Visit: https://dev-auth.testimonialtree.com/if/flow/initial-setup/"
echo "2. Or try: https://dev-auth.testimonialtree.com/"
echo "3. Set up the admin password and email through the web interface"
echo "4. After setup, login with username 'akadmin' and your chosen password"
echo
print_warning "The initial setup flow will only be available until the first admin user is fully configured."
echo