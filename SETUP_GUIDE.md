# Authentik Custom Docker Setup Guide

This guide provides step-by-step instructions for running Authentik with a custom Docker configuration.

## Prerequisites

- Docker and Docker Compose installed on your system
- Git (for cloning the repository)
- At least 4GB of available RAM
- Ports 9000, 9443, and 5435 available on your system

## Project Structure

```
authentik/
├── docker-compose.yml      # Docker Compose configuration
├── Dockerfile.custom       # Custom Docker image definition
├── .env                   # Environment variables (create this)
└── authentik/             # Source code directory
    └── providers/
        └── oauth2/
            └── views/
                └── token.py  # Modified OAuth2 token endpoint
```

## Step 1: Environment Configuration

Create a `.env` file in the project root with the following required variables:

```bash
# Database Configuration
PG_USER=authentik
PG_PASS=your_secure_database_password
PG_DB=authentik

# Authentik Configuration
AUTHENTIK_SECRET_KEY=your_very_secure_secret_key_here

# Optional: Port Configuration
COMPOSE_PORT_HTTP=9000
COMPOSE_PORT_HTTPS=9443
```

**Important**: Replace the placeholder values with secure passwords. You can generate secure keys using:
```bash
openssl rand -base64 32
```

## Step 2: Custom Dockerfile

The `Dockerfile.custom` extends the official Authentik image with your modifications:

```dockerfile
# Use the official authentik server image as base
FROM ghcr.io/goauthentik/server:2024.8.3

# Copy the modified token.py file with cache bust
RUN echo "Cache bust: $(date)"
COPY authentik/providers/oauth2/views/token.py /authentik/providers/oauth2/views/token.py

# Ensure proper permissions
USER root
RUN chown -R authentik:authentik /authentik/providers/oauth2/views/token.py
USER authentik
```

## Step 3: Docker Compose Configuration

The `docker-compose.yml` file defines all required services:

### Deployment Strategy Comparison

**Local Development**: Both server and worker use the same custom image (`authentik-custom:latest`) that includes OAuth2 modifications.

**Dev Environment (Working)**: Both server and worker use custom ECR image. Dev appears to be working despite this configuration, suggesting the dev custom image may support both commands.

**Production (Fixed)**: Uses a mixed strategy for reliability:
- **Server**: Uses custom ECR image with OAuth2 modifications
- **Worker**: Uses official Authentik image (`ghcr.io/goauthentik/server:2024.8.3`) since workers don't handle OAuth2 tokens

This production approach ensures workers have access to the full, tested worker functionality while servers get the custom OAuth2 behavior. **The dev environment should be updated to use this same strategy.**

```yaml
services:
  postgresql:
    image: docker.io/library/postgres:16-alpine
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
    volumes:
      - database:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${PG_DB:-authentik}
      POSTGRES_USER: ${PG_USER:-authentik}
      POSTGRES_PASSWORD: ${PG_PASS:?database password required}
    env_file:
      - .env
    ports:
      - "5432:5432"

  redis:
    image: docker.io/library/redis:alpine
    restart: unless-stopped
    command: --save 60 1 --loglevel warning
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
      interval: 30s
      timeout: 3s
      retries: 5
      start_period: 20s
    volumes:
      - redis:/data

  server:
    image: authentik-custom:latest
    restart: unless-stopped
    command: server
    environment:
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY:?secret key required}
    volumes:
      - ./media:/media
      - ./custom-templates:/templates
    env_file:
      - .env
    ports:
      - ${COMPOSE_PORT_HTTP:-9000}:9000
      - ${COMPOSE_PORT_HTTPS:-9443}:9443
    depends_on:
      postgresql:
        condition: service_healthy
      redis:
        condition: service_healthy

  worker:
    image: authentik-custom:latest
    restart: unless-stopped
    command: worker
    environment:
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY:?secret key required}
    user: root
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./media:/media
      - ./certs:/certs
      - ./custom-templates:/templates
    env_file:
      - .env
    depends_on:
      postgresql:
        condition: service_healthy
      redis:
        condition: service_healthy

volumes:
  database:
    driver: local
  redis:
    driver: local
```

## Step 4: Building and Running

### 1. Build the Custom Docker Image

**For Local Development:**
```bash
docker build -f Dockerfile.custom -t authentik-custom:latest .
```

**For Production Deployment (AWS Fargate):**
```bash
# Must specify linux/amd64 platform for AWS Fargate compatibility
docker buildx build --platform linux/amd64 -f Dockerfile.custom -t authentik-custom:latest .
```

**Note**: AWS Fargate requires `linux/amd64` architecture. Building without `--platform linux/amd64` may result in "Exec format error" when deploying to ECS.

### 2. Start the Services

```bash
# Start all services in the background
docker-compose up -d
```

### 3. Check Service Status

```bash
# View running containers
docker ps

# View logs
docker-compose logs -f

# Check specific service logs
docker-compose logs server
```

### 4. Run Database Migrations (First Time Only)

```bash
docker-compose exec server python -m lifecycle.migrate
```

### 5. Create Admin User (First Time Only)

If the default admin user doesn't exist or you need to reset the password:

```bash
# Reset password for default admin user (akadmin)
docker-compose exec server python manage.py shell -c "from authentik.core.models import User; u = User.objects.get(username='akadmin'); u.set_password('admin'); u.save(); print('Password reset successfully')"
```

## Step 5: Accessing Authentik

Once all services are running, you can access Authentik at:

- **URL**: http://localhost:9000
- **Username**: `akadmin`
- **Password**: `admin` (or whatever you set in the previous step)

## Common Operations

### Stop Services

```bash
docker-compose down
```

### Stop and Remove Volumes (Clean Slate)

```bash
docker-compose down -v
```

### View Service Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f server
```

### Restart a Service

```bash
docker-compose restart server
```

### Execute Commands in Container

```bash
# Django shell
docker-compose exec server python manage.py shell

# Run migrations
docker-compose exec server python -m lifecycle.migrate
```

## Troubleshooting

### Cannot Login

1. Check server logs: `docker-compose logs server`
2. Ensure database migrations have run
3. Try resetting the admin password using the command above

### Port Already in Use

If ports 9000, 9443, or 5435 are already in use, modify the port mappings in `.env`:

```bash
COMPOSE_PORT_HTTP=9001
COMPOSE_PORT_HTTPS=9444
```

### Database Connection Issues

1. Ensure PostgreSQL is healthy: `docker-compose ps`
2. Check PostgreSQL logs: `docker-compose logs postgresql`
3. Verify environment variables in `.env`

### Memory Issues

If containers are being killed, increase Docker's memory allocation in Docker Desktop settings.

## Security Considerations

1. **Change Default Passwords**: Always change the default admin password immediately after setup
2. **Use Strong Secret Keys**: Generate cryptographically secure secret keys
3. **HTTPS in Production**: Use a reverse proxy with SSL certificates for production deployments
4. **Firewall Rules**: Restrict access to database ports (5435) in production
5. **Regular Updates**: Keep the base image version updated in `Dockerfile.custom`

## Additional Resources

- [Official Authentik Documentation](https://goauthentik.io/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## Support

For issues specific to this custom setup, check:
1. Container logs using `docker-compose logs`
2. Authentik's built-in system info at http://localhost:9000/-/health/live/
3. The official Authentik GitHub repository for known issues