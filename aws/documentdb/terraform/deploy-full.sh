#!/bin/bash

# Master Deployment Script for Open Saves AWS
# This script orchestrates the deployment of all 5 independent Terraform steps

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
CLUSTER_NAME="open-saves-cluster"
ECR_REPO_NAME="open-saves"
NAMESPACE="open-saves"
ENVIRONMENT="dev"
SOURCE_PATH="/home/ec2-user/projects/open-saves-aws/aws"
SKIP_STEPS=""
ONLY_STEPS=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a step should be executed
should_execute_step() {
    local step=$1
    
    # If ONLY_STEPS is set, only execute those steps
    if [ -n "$ONLY_STEPS" ]; then
        if [[ "$ONLY_STEPS" == *"$step"* ]]; then
            return 0
        else
            return 1
        fi
    fi
    
    # If SKIP_STEPS is set, skip those steps
    if [ -n "$SKIP_STEPS" ]; then
        if [[ "$SKIP_STEPS" == *"$step"* ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to wait for user confirmation
confirm_step() {
    local step_name=$1
    local step_description=$2
    
    echo ""
    echo "=========================================="
    echo "Ready to deploy: $step_name"
    echo "Description: $step_description"
    echo "=========================================="
    
    if [ "$INTERACTIVE" = "true" ]; then
        read -p "Continue with this step? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Skipping $step_name"
            return 1
        fi
    fi
    
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is required but not installed"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        exit 1
    fi
    
    # Check Go
    if ! command -v go &> /dev/null; then
        print_error "Go is required but not installed"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is recommended for Kubernetes management"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check source path
    if [ ! -d "$SOURCE_PATH" ]; then
        print_error "Source path does not exist: $SOURCE_PATH"
        exit 1
    fi
    
    if [ ! -f "$SOURCE_PATH/main.go" ]; then
        print_error "main.go not found in source path: $SOURCE_PATH"
        exit 1
    fi
    
    print_success "All prerequisites satisfied"
}

# Function to display deployment summary
show_summary() {
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Region: $REGION"
    echo "Architecture: $ARCHITECTURE"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "ECR Repository: $ECR_REPO_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Environment: $ENVIRONMENT"
    echo "Source Path: $SOURCE_PATH"
    
    if [ -n "$SKIP_STEPS" ]; then
        echo "Skipping Steps: $SKIP_STEPS"
    fi
    
    if [ -n "$ONLY_STEPS" ]; then
        echo "Only Steps: $ONLY_STEPS"
    fi
    
    echo ""
    echo "Steps to be executed:"
    should_execute_step "1" && echo "  ✓ Step 1: EKS Cluster and ECR Repository"
    should_execute_step "2" && echo "  ✓ Step 2: Data Infrastructure"
    should_execute_step "3" && echo "  ✓ Step 3: Container Images"
    should_execute_step "4" && echo "  ✓ Step 4: Compute and Application"
    should_execute_step "5" && echo "  ✓ Step 5: CloudFront and WAF"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --architecture)
            ARCHITECTURE="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --ecr-repo-name)
            ECR_REPO_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --source-path)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --skip-steps)
            SKIP_STEPS="$2"
            shift 2
            ;;
        --only-steps)
            ONLY_STEPS="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Master deployment script for Open Saves AWS infrastructure"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture (amd64|arm64, default: amd64)"
            echo "  --cluster-name NAME          EKS cluster name (default: open-saves-cluster)"
            echo "  --ecr-repo-name NAME         ECR repository name (default: open-saves)"
            echo "  --namespace NAMESPACE        Kubernetes namespace (default: open-saves)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --source-path PATH           Path to source code (default: /home/ec2-user/projects/open-saves-aws/aws)"
            echo "  --skip-steps STEPS           Skip specific steps (e.g., '1,3,5')"
            echo "  --only-steps STEPS           Only execute specific steps (e.g., '2,4')"
            echo "  --interactive                Prompt for confirmation before each step"
            echo "  --help                       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Deploy everything with defaults"
            echo "  $0 --architecture arm64               # Deploy for ARM64"
            echo "  $0 --skip-steps '1,2'                 # Skip steps 1 and 2"
            echo "  $0 --only-steps '3,4,5'               # Only deploy steps 3, 4, and 5"
            echo "  $0 --interactive                      # Prompt before each step"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    print_error "Architecture must be 'amd64' or 'arm64'"
    exit 1
fi

# Main deployment logic
main() {
    print_status "Starting Open Saves AWS deployment..."
    
    check_prerequisites
    show_summary
    
    if [ "$INTERACTIVE" = "true" ]; then
        read -p "Proceed with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    local start_time=$(date +%s)
    local failed_steps=()
    
    # Step 1: EKS Cluster and ECR Repository
    if should_execute_step "1"; then
        if confirm_step "Step 1" "EKS Cluster and ECR Repository"; then
            print_status "Executing Step 1..."
            if ! "$SCRIPT_DIR/deploy-step1.sh" \
                --region "$REGION" \
                --cluster-name "$CLUSTER_NAME" \
                --ecr-repo-name "$ECR_REPO_NAME" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 1 failed"
                failed_steps+=("1")
            else
                print_success "Step 1 completed successfully"
            fi
        fi
    fi
    
    # Step 2: Data Infrastructure
    if should_execute_step "2"; then
        if confirm_step "Step 2" "Data Infrastructure (DocumentDB, S3, ElastiCache)"; then
            print_status "Executing Step 2..."
            if ! "$SCRIPT_DIR/deploy-step2.sh" \
                --region "$REGION" \
                --architecture "$ARCHITECTURE" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 2 failed"
                failed_steps+=("2")
            else
                print_success "Step 2 completed successfully"
            fi
        fi
    fi
    
    # Step 3: Container Images
    if should_execute_step "3"; then
        if confirm_step "Step 3" "Container Images (Build and Push)"; then
            print_status "Executing Step 3..."
            if ! "$SCRIPT_DIR/deploy-step3.sh" \
                --region "$REGION" \
                --architecture "$ARCHITECTURE" \
                --source-path "$SOURCE_PATH" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 3 failed"
                failed_steps+=("3")
            else
                print_success "Step 3 completed successfully"
            fi
        fi
    fi
    
    # Step 4: Compute and Application
    if should_execute_step "4"; then
        if confirm_step "Step 4" "Compute and Application (EKS Nodes, Kubernetes)"; then
            print_status "Executing Step 4..."
            if ! "$SCRIPT_DIR/deploy-step4.sh" \
                --region "$REGION" \
                --architecture "$ARCHITECTURE" \
                --namespace "$NAMESPACE" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 4 failed"
                failed_steps+=("4")
            else
                print_success "Step 4 completed successfully"
            fi
        fi
    fi
    
    # Step 5: CloudFront and WAF
    if should_execute_step "5"; then
        if confirm_step "Step 5" "CloudFront and WAF (Security and Performance)"; then
            print_status "Executing Step 5..."
            if ! "$SCRIPT_DIR/deploy-step5.sh" \
                --region "$REGION" \
                --architecture "$ARCHITECTURE" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 5 failed"
                failed_steps+=("5")
            else
                print_success "Step 5 completed successfully"
            fi
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT COMPLETE"
    echo "=========================================="
    echo "Total Duration: $((duration / 60)) minutes $((duration % 60)) seconds"
    
    if [ ${#failed_steps[@]} -eq 0 ]; then
        print_success "All steps completed successfully!"
        
        # Display final endpoints if Step 4 and 5 were executed
        if should_execute_step "4" && should_execute_step "5"; then
            echo ""
            echo "Application Endpoints:"
            
            # Get load balancer hostname
            if LB_HOSTNAME=$(aws ssm get-parameter --name "/open-saves/step4/load_balancer_hostname_${ARCHITECTURE}" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
                echo "  Direct Load Balancer:"
                echo "    HTTP API: http://$LB_HOSTNAME:8080"
                echo "    gRPC API: $LB_HOSTNAME:8081"
            fi
            
            # Get CloudFront domain
            if CF_DOMAIN=$(aws ssm get-parameter --name "/open-saves/step5/cloudfront_domain_name_${ARCHITECTURE}" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
                echo "  CloudFront CDN:"
                echo "    HTTPS API: https://$CF_DOMAIN"
            fi
        fi
        
        echo ""
        echo "Next Steps:"
        echo "  1. Test the API endpoints above"
        echo "  2. Monitor via CloudWatch dashboards"
        echo "  3. Review security settings in WAF console"
        
    else
        print_error "Some steps failed: ${failed_steps[*]}"
        echo ""
        echo "To retry failed steps:"
        for step in "${failed_steps[@]}"; do
            echo "  ./deploy-step${step}.sh [options]"
        done
        exit 1
    fi
}

# Execute main function
main "$@"
