#!/bin/bash

################################################################################
# Maximo Connector - Build and Push Script
# 
# This script builds the connector using Maven in Docker and pushes the image
# to a container registry.
#
# Required Environment Variables:
#   REGISTRY_URL      - Container registry URL (e.g., docker.io, ghcr.io, quay.io)
#   REGISTRY_USERNAME - Registry username
#   REGISTRY_PASSWORD - Registry password or token
#   IMAGE_NAME        - Image name (e.g., myorg/maximo-connector)
#   IMAGE_TAG         - Image tag (default: latest)
#
# Optional Environment Variables:
#   MAVEN_IMAGE       - Maven Docker image to use (default: maven:3.9-eclipse-temurin-21)
#   BUILD_ARGS        - Additional docker build arguments
#
# Usage:
#   export REGISTRY_URL="docker.io"
#   export REGISTRY_USERNAME="myusername"
#   export REGISTRY_PASSWORD="mypassword"
#   export IMAGE_NAME="myorg/maximo-connector"
#   export IMAGE_TAG="1.0.0"
#   ./build-and-push.sh
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
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

# Function to check required environment variables
check_env_vars() {
    local missing_vars=()
    
    if [ -z "${REGISTRY_URL:-}" ]; then
        missing_vars+=("REGISTRY_URL")
    fi
    
    if [ -z "${REGISTRY_USERNAME:-}" ]; then
        missing_vars+=("REGISTRY_USERNAME")
    fi
    
    if [ -z "${REGISTRY_PASSWORD:-}" ]; then
        missing_vars+=("REGISTRY_PASSWORD")
    fi
    
    if [ -z "${IMAGE_NAME:-}" ]; then
        missing_vars+=("IMAGE_NAME")
    fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Example usage:"
        echo "  export REGISTRY_URL=\"docker.io\""
        echo "  export REGISTRY_USERNAME=\"myusername\""
        echo "  export REGISTRY_PASSWORD=\"mypassword\""
        echo "  export IMAGE_NAME=\"myorg/maximo-connector\""
        echo "  export IMAGE_TAG=\"latest\""
        echo "  ./build-and-push.sh"
        exit 1
    fi
}

# Check required environment variables FIRST
check_env_vars

# Set default values for optional variables
MAVEN_IMAGE="${MAVEN_IMAGE:-maven:3.9-eclipse-temurin-21}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_ARGS="${BUILD_ARGS:-}"

# Construct full image name
FULL_IMAGE_NAME="${REGISTRY_URL}/${IMAGE_NAME}:${IMAGE_TAG}"

log_info "Starting Maximo Connector build and push process"
echo "=================================================="
echo "Registry URL:    ${REGISTRY_URL}"
echo "Image Name:      ${IMAGE_NAME}"
echo "Image Tag:       ${IMAGE_TAG}"
echo "Full Image:      ${FULL_IMAGE_NAME}"
echo "Maven Image:     ${MAVEN_IMAGE}"
echo "=================================================="
echo ""

# Detect container runtime (Docker or Podman)
CONTAINER_CMD=""
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
    log_success "Podman detected and will be used"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
    log_success "Docker detected and will be used"
else
    log_error "Neither Docker nor Podman is installed or in PATH"
    log_error "Please install either Docker or Podman to continue"
    exit 1
fi

# Check if container runtime is working
if ! $CONTAINER_CMD info &> /dev/null; then
    log_error "$CONTAINER_CMD is not running or not accessible"
    if [ "$CONTAINER_CMD" = "docker" ]; then
        log_error "Try starting Docker Desktop or Docker daemon"
    fi
    exit 1
fi

log_success "$CONTAINER_CMD is running and accessible"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

log_info "Working directory: $SCRIPT_DIR"

# Step 1: Clean previous builds
log_info "Cleaning previous builds..."
if [ -d "target" ]; then
    rm -rf target
    log_success "Cleaned target directory"
fi

# Step 2: Build the application using Maven in container
log_info "Building application with Maven (in $CONTAINER_CMD container)..."
$CONTAINER_CMD run --rm \
    -v "$SCRIPT_DIR":/workspace \
    -v "$HOME/.m2":/root/.m2 \
    -w /workspace \
    "$MAVEN_IMAGE" \
    mvn clean package -DskipTests

if [ $? -eq 0 ]; then
    log_success "Maven build completed successfully"
else
    log_error "Maven build failed"
    exit 1
fi

# Verify WAR file was created
if [ ! -f "target/ticket-template.war" ]; then
    log_error "WAR file not found at target/ticket-template.war"
    exit 1
fi

log_success "WAR file created: target/ticket-template.war"

# Step 3: Build container image
log_info "Building container image: ${FULL_IMAGE_NAME}"
$CONTAINER_CMD build \
    -t "${FULL_IMAGE_NAME}" \
    -f container/Dockerfile \
    ${BUILD_ARGS} \
    .

if [ $? -eq 0 ]; then
    log_success "Container image built successfully"
else
    log_error "Container build failed"
    exit 1
fi

# Step 4: Login to container registry
log_info "Logging in to container registry: ${REGISTRY_URL}"
echo "${REGISTRY_PASSWORD}" | $CONTAINER_CMD login "${REGISTRY_URL}" \
    --username "${REGISTRY_USERNAME}" \
    --password-stdin

if [ $? -eq 0 ]; then
    log_success "Successfully logged in to ${REGISTRY_URL}"
else
    log_error "Failed to login to container registry"
    exit 1
fi

# Step 5: Push image to registry
log_info "Pushing image to registry: ${FULL_IMAGE_NAME}"
$CONTAINER_CMD push "${FULL_IMAGE_NAME}"

if [ $? -eq 0 ]; then
    log_success "Image pushed successfully"
else
    log_error "Failed to push image"
    exit 1
fi

# Step 6: Tag as latest if not already
if [ "${IMAGE_TAG}" != "latest" ]; then
    LATEST_IMAGE="${REGISTRY_URL}/${IMAGE_NAME}:latest"
    log_info "Tagging image as latest: ${LATEST_IMAGE}"
    $CONTAINER_CMD tag "${FULL_IMAGE_NAME}" "${LATEST_IMAGE}"
    $CONTAINER_CMD push "${LATEST_IMAGE}"
    
    if [ $? -eq 0 ]; then
        log_success "Latest tag pushed successfully"
    else
        log_warning "Failed to push latest tag (non-critical)"
    fi
fi

# Step 7: Logout from registry
log_info "Logging out from container registry"
$CONTAINER_CMD logout "${REGISTRY_URL}" &> /dev/null

# Summary
echo ""
echo "=================================================="
log_success "Build and push completed successfully!"
echo "=================================================="
echo "Image Details:"
echo "  Full Image: ${FULL_IMAGE_NAME}"
echo "  Size: $($CONTAINER_CMD images ${FULL_IMAGE_NAME} --format "{{.Size}}")"
echo ""
echo "To pull this image:"
echo "  $CONTAINER_CMD pull ${FULL_IMAGE_NAME}"
echo ""
echo "To run this image:"
echo "  $CONTAINER_CMD run -p 8080:9443 ${FULL_IMAGE_NAME}"
echo "=================================================="

# Made with Bob
