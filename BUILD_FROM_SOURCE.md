# Building and Running Authentik from Source

This guide explains how to build and run Authentik completely from the source code in this directory, without relying on the pre-built base image.

## Prerequisites

- Docker and Docker Compose installed
- At least 8GB of RAM available for the build process
- About 10GB of free disk space
- Git (for build hash generation)

## Quick Start

1. **Build the image from source:**
   ```bash
   ./build-from-source.sh
   ```
   This will create a Docker image tagged as `authentik-source:latest`

2. **Run using the source-built image:**
   ```bash
   docker-compose -f docker-compose.source.yml up -d
   ```

## What's Different?

### Original Approach (Dockerfile.custom)
- Uses pre-built base image: `ghcr.io/goauthentik/server:2024.8.3`
- Only replaces the modified `token.py` file
- Smaller build time, but depends on external image

### Source Build Approach (Dockerfile.source)
- Builds everything from scratch
- Compiles the Go binaries
- Builds the web UI from TypeScript/JavaScript source
- Installs all Python dependencies
- Complete control over the build process

## Build Process Overview

The source build follows these stages:

1. **Web UI Build (Node.js)**
   - Installs npm dependencies
   - Builds the web interface
   - Generates static assets

2. **Go Binary Build**
   - Compiles the Go server binary
   - Includes LDAP, proxy, RAC, and RADIUS components

3. **Python Dependencies**
   - Sets up Python virtual environment
   - Installs all Python packages from `pyproject.toml`
   - Builds native extensions (cryptography, lxml, etc.)

4. **Final Image Assembly**
   - Combines all components
   - Sets up runtime environment
   - Configures user permissions

## Customization

Since you're building from source, you can now:

1. **Modify any Python code** - Changes will be included in the build
2. **Update frontend code** - Modify TypeScript/JavaScript in `/web`
3. **Change Go code** - Update server components in `/cmd` and `/internal`
4. **Add new dependencies** - Update `pyproject.toml` or `package.json`

## Building with Custom Changes

If you've made changes to the code:

```bash
# Rebuild the image
./build-from-source.sh

# Restart services with new image
docker-compose -f docker-compose.source.yml down
docker-compose -f docker-compose.source.yml up -d
```

## Troubleshooting

### Build Failures

1. **Node.js build errors:**
   - Check `web/package.json` dependencies
   - Ensure Node.js version compatibility

2. **Go build errors:**
   - Verify Go version (requires 1.23+)
   - Check CGO dependencies for your platform

3. **Python dependency errors:**
   - Some packages require system libraries
   - Check the Dockerfile for required apt packages

### Runtime Issues

1. **Database connection errors:**
   - Ensure PostgreSQL is running
   - Check `.env` file for correct credentials

2. **Missing GeoIP databases:**
   - The source build tries to download free GeoLite2 databases
   - For production, use MaxMind license

## Environment Variables

Create a `.env` file with:

```env
PG_DB=authentik
PG_USER=authentik
PG_PASS=your-secure-password
AUTHENTIK_SECRET_KEY=your-very-long-random-secret-key
```

## Development Workflow

For active development:

1. **Make code changes**
2. **Rebuild only what's needed:**
   - For Python changes: Rebuild final stage only
   - For frontend changes: Rebuild from node-builder stage
   - For Go changes: Rebuild from go-builder stage

3. **Use Docker build cache:**
   ```bash
   docker build --target python-deps -t authentik-deps:latest -f Dockerfile.source .
   ```

## Production Considerations

- The source build doesn't include FIPS compliance (unlike the official image)
- GeoIP databases should be properly licensed for production use
- Consider multi-stage caching for faster rebuilds
- Set proper resource limits in docker-compose

## Reverting to Custom Image

To go back to using the modified base image:

```bash
docker-compose down
docker-compose up -d
```

This will use the original `docker-compose.yml` with `authentik-custom:latest`.