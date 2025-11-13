#!/bin/bash

# Build script for Authentik from source code

echo "Building Authentik from source code..."

# Set build arguments
export GIT_BUILD_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
export VERSION="2025.10.0-rc1-source"

# Build the Docker image
echo "Building Docker image..."
docker build \
    --build-arg GIT_BUILD_HASH=$GIT_BUILD_HASH \
    --build-arg VERSION=$VERSION \
    -f Dockerfile.source \
    -t authentik-source:latest \
    -t authentik-source:$VERSION \
    .

if [ $? -eq 0 ]; then
    echo "Build completed successfully!"
    echo "Image tagged as:"
    echo "  - authentik-source:latest"
    echo "  - authentik-source:$VERSION"
    echo ""
    echo "To run the container, update docker-compose.yml to use 'authentik-source:latest' instead of 'authentik-custom:latest'"
else
    echo "Build failed!"
    exit 1
fi