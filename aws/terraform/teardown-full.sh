#!/bin/bash

# Master Teardown Script for Open Saves AWS
# This script orchestrates the teardown of all 5 independent Terraform steps in reverse order

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
CLUSTER_NAME="open-saves-cluster"
ECR_REPO_NAME="open-saves"
NAMESPACE="open-saves"
ENVIRONMENT="dev"
SKIP_STEPS=""
ONLY_STEPS=""
DELETE_IMAGES="false"
EMPTY_S3="false"
DELETE_ECR_IMAGES="false"

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
    echo "Ready to teardown: $step_name"
    echo "Description: $step_description"
    echo "=========================================="
    
    if [ "$INTERACTIVE" = "true" ]; then
        read -p "Continue with this teardown step? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Skipping $step_name"
            return 1
        fi
    fi
    
    return 0
}

# Function to display teardown summary
show_summary() {
    echo ""
    echo "=========================================="
    echo "TEARDOWN SUMMARY"
    echo "=========================================="
    echo "Region: $REGION"
    echo "Architecture: $ARCHITECTURE"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "ECR Repository: $ECR_REPO_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Environment: $ENVIRONMENT"
    echo "Delete Container Images: $DELETE_IMAGES"
    echo "Empty S3 Bucket: $EMPTY_S3"
    echo "Delete ECR Images: $DELETE_ECR_IMAGES"
    
    if [ -n "$SKIP_STEPS" ]; then
        echo "Skipping Steps: $SKIP_STEPS"
    fi
    
    if [ -n "$ONLY_STEPS" ]; then
        echo "Only Steps: $ONLY_STEPS"
    fi
    
    echo ""
    echo "Steps to be executed (in reverse order):"
    should_execute_step "5" && echo "  ✓ Step 5: CloudFront and WAF"
    should_execute_step "4" && echo "  ✓ Step 4: Compute and Application"
    should_execute_step "3" && echo "  ✓ Step 3: Container Images"
    should_execute_step "2" && echo "  ✓ Step 2: Data Infrastructure"
    should_execute_step "1" && echo "  ✓ Step 1: EKS Cluster and ECR Repository"
    echo ""
    
    print_warning "This will permanently destroy all Open Saves infrastructure!"
    print_warning "Make sure you have backed up any important data."
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
        --skip-steps)
            SKIP_STEPS="$2"
            shift 2
            ;;
        --only-steps)
            ONLY_STEPS="$2"
            shift 2
            ;;
        --delete-images)
            DELETE_IMAGES="true"
            shift
            ;;
        --empty-s3)
            EMPTY_S3="true"
            shift
            ;;
        --delete-ecr-images)
            DELETE_ECR_IMAGES="true"
            shift
            ;;
        --interactive)
            INTERACTIVE="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Master teardown script for Open Saves AWS infrastructure"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture (amd64|arm64, default: amd64)"
            echo "  --cluster-name NAME          EKS cluster name (default: open-saves-cluster)"
            echo "  --ecr-repo-name NAME         ECR repository name (default: open-saves)"
            echo "  --namespace NAMESPACE        Kubernetes namespace (default: open-saves)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --skip-steps STEPS           Skip specific steps (e.g., '1,3,5')"
            echo "  --only-steps STEPS           Only execute specific steps (e.g., '2,4')"
            echo "  --delete-images              Delete container images from ECR (Step 3)"
            echo "  --empty-s3                   Empty S3 bucket before destroying (Step 2)"
            echo "  --delete-ecr-images          Delete all ECR images before destroying repository (Step 1)"
            echo "  --interactive                Prompt for confirmation before each step"
            echo "  --help                       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Teardown everything with defaults"
            echo "  $0 --architecture arm64               # Teardown ARM64 deployment"
            echo "  $0 --delete-images --empty-s3         # Clean up all data before teardown"
            echo "  $0 --skip-steps '1,2'                 # Skip steps 1 and 2"
            echo "  $0 --only-steps '4,5'                 # Only teardown steps 4 and 5"
            echo "  $0 --interactive                      # Prompt before each step"
            echo ""
            echo "Note: Steps are executed in reverse order (5→4→3→2→1) to respect dependencies"
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

# Main teardown logic
main() {
    print_status "Starting Open Saves AWS teardown..."
    
    show_summary
    
    if [ "$INTERACTIVE" = "true" ]; then
        read -p "Proceed with teardown? This cannot be undone! (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Teardown cancelled by user"
            exit 0
        fi
    else
        print_warning "Starting teardown in 10 seconds... Press Ctrl+C to cancel"
        sleep 10
    fi
    
    local start_time=$(date +%s)
    local failed_steps=()
    
    # Step 5: CloudFront and WAF (teardown first)
    if should_execute_step "5"; then
        if confirm_step "Step 5" "CloudFront and WAF"; then
            print_status "Tearing down Step 5..."
            if ! "$SCRIPT_DIR/teardown-step5.sh" \
                --region "$REGION" \
                --architecture "$ARCHITECTURE" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 5 teardown failed"
                failed_steps+=("5")
            else
                print_success "Step 5 teardown completed successfully"
            fi
        fi
    fi
    
    # Step 4: Compute and Application
    if should_execute_step "4"; then
        if confirm_step "Step 4" "Compute and Application"; then
            print_status "Tearing down Step 4..."
            if ! "$SCRIPT_DIR/teardown-step4.sh" \
                --region "$REGION" \
                --architecture "$ARCHITECTURE" \
                --namespace "$NAMESPACE" \
                --environment "$ENVIRONMENT"; then
                print_error "Step 4 teardown failed"
                failed_steps+=("4")
            else
                print_success "Step 4 teardown completed successfully"
            fi
        fi
    fi
    
    # Step 3: Container Images
    if should_execute_step "3"; then
        if confirm_step "Step 3" "Container Images"; then
            print_status "Tearing down Step 3..."
            local step3_args=(
                --region "$REGION"
                --architecture "$ARCHITECTURE"
                --environment "$ENVIRONMENT"
            )
            
            if [ "$DELETE_IMAGES" = "true" ]; then
                step3_args+=(--delete-images)
            fi
            
            if ! "$SCRIPT_DIR/teardown-step3.sh" "${step3_args[@]}"; then
                print_error "Step 3 teardown failed"
                failed_steps+=("3")
            else
                print_success "Step 3 teardown completed successfully"
            fi
        fi
    fi
    
    # Step 2: Data Infrastructure
    if should_execute_step "2"; then
        if confirm_step "Step 2" "Data Infrastructure"; then
            print_status "Tearing down Step 2..."
            local step2_args=(
                --region "$REGION"
                --architecture "$ARCHITECTURE"
                --environment "$ENVIRONMENT"
            )
            
            if [ "$EMPTY_S3" = "true" ]; then
                step2_args+=(--empty-s3)
            fi
            
            if ! "$SCRIPT_DIR/teardown-step2.sh" "${step2_args[@]}"; then
                print_error "Step 2 teardown failed"
                failed_steps+=("2")
            else
                print_success "Step 2 teardown completed successfully"
            fi
        fi
    fi
    
    # Step 1: EKS Cluster and ECR Repository (teardown last)
    if should_execute_step "1"; then
        if confirm_step "Step 1" "EKS Cluster and ECR Repository"; then
            print_status "Tearing down Step 1..."
            local step1_args=(
                --region "$REGION"
                --cluster-name "$CLUSTER_NAME"
                --ecr-repo-name "$ECR_REPO_NAME"
                --environment "$ENVIRONMENT"
            )
            
            if [ "$DELETE_ECR_IMAGES" = "true" ]; then
                step1_args+=(--delete-ecr-images)
            fi
            
            if ! "$SCRIPT_DIR/teardown-step1.sh" "${step1_args[@]}"; then
                print_error "Step 1 teardown failed"
                failed_steps+=("1")
            else
                print_success "Step 1 teardown completed successfully"
            fi
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "=========================================="
    echo "TEARDOWN COMPLETE"
    echo "=========================================="
    echo "Total Duration: $((duration / 60)) minutes $((duration % 60)) seconds"
    
    if [ ${#failed_steps[@]} -eq 0 ]; then
        print_success "All teardown steps completed successfully!"
        print_success "Open Saves AWS infrastructure has been completely removed."
        
        # Clean up any remaining SSM parameters
        print_status "Cleaning up any remaining SSM parameters..."
        aws ssm get-parameters-by-path --path "/open-saves/" --region "$REGION" --query 'Parameters[].Name' --output text 2>/dev/null | \
        xargs -r -n1 aws ssm delete-parameter --region "$REGION" --name 2>/dev/null || true
        
    else
        print_error "Some teardown steps failed: ${failed_steps[*]}"
        echo ""
        echo "To retry failed steps:"
        for step in "${failed_steps[@]}"; do
            echo "  ./teardown-step${step}.sh [options]"
        done
        
        echo ""
        print_warning "You may need to manually clean up remaining resources in the AWS console"
        exit 1
    fi
}

# Execute main function
main "$@"
