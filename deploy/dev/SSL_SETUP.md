# SSL Certificate Setup for Authentik Dev Environment

This document outlines the SSL certificate setup options for the Authentik development environment with domain `dev-auth.testimonialtree.com`.

## Option 1: AWS Certificate Manager (ACM) - Recommended

AWS Certificate Manager provides free SSL certificates with automatic renewal.

### Prerequisites
- Domain `testimonialtree.com` must be configured in Route 53 or have DNS validation access
- Application Load Balancer (ALB) or CloudFront distribution

### Steps

1. **Request Certificate**:
   ```bash
   aws acm request-certificate \
     --domain-name dev-auth.testimonialtree.com \
     --validation-method DNS \
     --region us-west-2
   ```

2. **DNS Validation**:
   - ACM will provide DNS records to add to your domain
   - Add the CNAME records to your DNS provider
   - Wait for validation (usually 5-30 minutes)

3. **Attach to Load Balancer**:
   - Configure ALB listener on port 443
   - Select the ACM certificate
   - Redirect HTTP (port 80) to HTTPS (port 443)

### ALB Configuration Example

```bash
# Create HTTPS listener
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-west-2:account:loadbalancer/app/authentik-dev-alb/... \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:us-west-2:account:certificate/... \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-west-2:account:targetgroup/...

# Create HTTP redirect rule
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-west-2:account:loadbalancer/app/authentik-dev-alb/... \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'
```

## Option 2: Let's Encrypt with Certbot (EC2 Deployment)

For direct EC2 deployment, use Let's Encrypt certificates with automatic renewal.

### Prerequisites
- EC2 instance with public IP
- Domain pointing to EC2 public IP
- Nginx or Traefik reverse proxy

### Installation

```bash
# Install certbot
sudo apt update
sudo apt install certbot python3-certbot-nginx

# Request certificate
sudo certbot --nginx -d dev-auth.testimonialtree.com

# Test automatic renewal
sudo certbot renew --dry-run
```

### Nginx Configuration

```nginx
server {
    listen 80;
    server_name dev-auth.testimonialtree.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name dev-auth.testimonialtree.com;

    ssl_certificate /etc/letsencrypt/live/dev-auth.testimonialtree.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dev-auth.testimonialtree.com/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;

    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Docker Compose with Traefik

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.email=admin@testimonialtree.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
    labels:
      - "traefik.enable=true"

  server:
    # ... your authentik server config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.authentik.rule=Host(\`dev-auth.testimonialtree.com\`)"
      - "traefik.http.routers.authentik.entrypoints=websecure"
      - "traefik.http.routers.authentik.tls.certresolver=letsencrypt"
      - "traefik.http.services.authentik.loadbalancer.server.port=9000"
```

## Option 3: Self-Signed Certificate (Testing Only)

For local testing or internal development only.

### Generate Certificate

```bash
# Create directory for certificates
mkdir -p ./certs

# Generate private key
openssl genrsa -out ./certs/dev-auth.key 2048

# Generate certificate signing request
openssl req -new -key ./certs/dev-auth.key -out ./certs/dev-auth.csr \
  -subj "/C=US/ST=CA/L=San Francisco/O=TestimonialTree/CN=dev-auth.testimonialtree.com"

# Generate self-signed certificate
openssl x509 -req -in ./certs/dev-auth.csr -signkey ./certs/dev-auth.key \
  -out ./certs/dev-auth.crt -days 365

# Clean up CSR
rm ./certs/dev-auth.csr
```

## DNS Configuration

For all options, ensure DNS is configured:

```bash
# Create A record in Route 53
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "dev-auth.testimonialtree.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "YOUR_ALB_OR_EC2_IP"}]
      }
    }]
  }'
```

## Verification

Test your SSL setup:

```bash
# Test SSL certificate
curl -I https://dev-auth.testimonialtree.com

# Check certificate details
openssl s_client -connect dev-auth.testimonialtree.com:443 -servername dev-auth.testimonialtree.com

# Test with SSL Labs (for public domains)
# https://www.ssllabs.com/ssltest/analyze.html?d=dev-auth.testimonialtree.com
```

## Authentik Configuration

Update your `.env.dev` file to ensure SSL is properly configured:

```bash
# Domain & SSL Configuration
AUTHENTIK_COOKIE_DOMAIN=dev-auth.testimonialtree.com
AUTHENTIK_CSRF_COOKIE_SECURE=true
AUTHENTIK_SESSION_COOKIE_SECURE=true

# If behind a proxy (ALB/Nginx)
AUTHENTIK_WEB__DISABLE_X_FRAME_OPTIONS=true
```

## Troubleshooting

### Common Issues

1. **Certificate not trusted**: Self-signed certificates will show browser warnings
2. **Mixed content**: Ensure all resources load over HTTPS
3. **Redirect loops**: Check proxy configuration and Authentik settings
4. **Domain validation fails**: Verify DNS propagation and records

### Debug Commands

```bash
# Check certificate expiry
openssl x509 -in /path/to/certificate.crt -text -noout | grep "Not After"

# Test certificate chain
openssl verify -CAfile /path/to/ca-bundle.crt /path/to/certificate.crt

# Check DNS resolution
dig dev-auth.testimonialtree.com A

# Test port connectivity
telnet dev-auth.testimonialtree.com 443
```