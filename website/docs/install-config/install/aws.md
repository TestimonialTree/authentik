---
title: AWS installation
---

The previous AWS CloudFormation–based installer has been removed. For AWS deployments, we recommend one of the following supported paths instead:

- Docker Compose: run on EC2 or other hosts behind your own ALB/NGINX. See [Docker Compose](./docker-compose.mdx).
- Kubernetes on EKS: deploy using the official Helm chart. See [Kubernetes](./kubernetes.md).

If you maintain internal Terraform for AWS (ALB/ECS/RDS/CodePipeline), follow your Terraform documentation and CI/CD process.
