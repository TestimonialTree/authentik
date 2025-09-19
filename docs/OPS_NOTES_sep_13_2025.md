⚠️ **WARNING: The information in this document might be inaccurate and outdated.**

---

# Authentik Dev – Ops Checkpoint

**Document created:** September 13, 2025
**Last updated:** September 19, 2025

## Environment Snapshot (US‑East‑1)

- Cluster/Service: authentik-dev/authentik-dev
- Task definition: authentik-dev:17 (PRIMARY, 1/1 running)
- ALB DNS: authentik-dev-alb-799113490.us-east-1.elb.amazonaws.com
- Target group: arn:aws:elasticloadbalancing:us-east-1:597332957026:targetgroup/authentik-dev-tg/abfdf2bb02700f26 (healthy)
- RDS endpoint: authentik-dev-postgres.cxvehfmkaeag.us-east-1.rds.amazonaws.com:5432
- Logs: /ecs/authentik-dev (CloudWatch)

## CI/CD Pipeline

- Pipeline: authentik-dev-pipeline
- Build project: authentik-dev-build
- Source: S3 (authentik-dev-source-artifacts-kcihftn0/source.zip)
- Last run: Succeeded (latest execution after tagging updates)

## Container Image Policy

- ECR repo: 597332957026.dkr.ecr.us-east-1.amazonaws.com/authentik-dev
- Build tags (per run):
  - <short-commit> (e.g., yCxpxoU)
  - dev-<short-commit> (e.g., dev-yCxpxoU)
  - latest
- Lifecycle policy (applied):
  - Keep last 10 tags with prefix dev-
  - Keep last 5 tags named latest

## Recent Maintenance

- Fixed Deploy instability: ensured server starts correctly; ECS now stable
- Cleaned ECS task defs: kept :17, :16, :15, :14, :13; deregistered older
- Pruned ECR: deleted 8 untagged images
- Updated buildspec.yml: pushes dev-$IMAGE_TAG in addition to $IMAGE_TAG and latest

## Handy Commands

- Pipeline status:
  - aws codepipeline get-pipeline-state --name authentik-dev-pipeline \
    --query "stageStates[].{stage:stageName,status:latestExecution.status}"
- Build logs:
  - aws logs tail /aws/codebuild/authentik-dev-build --since 15m --format short
- Service health:
  - aws ecs describe-services --cluster authentik-dev --services authentik-dev \
    --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'
- Targets:
  - aws elbv2 describe-target-health --target-group-arn <tg-arn>
- Start a run:
  - ./deploy/dev/upload-source.sh (or upload source.zip to Source bucket) and
  - aws codepipeline start-pipeline-execution --name authentik-dev-pipeline

## Credentials Note

- SSO tokens expire; if Terraform or CLI fails with ExpiredToken:
  - aws sso login --profile authentik-dev

## Next Session Ideas

- Optional (dev speed): reduce ALB health-check interval to 10s
- Optional (cleanup): set a scheduled job to prune old task defs
- Verify DNS/SSL: ensure dev-auth.testimonialtree.com points at the ALB and cert is validated

---
This file is a quick checkpoint of current state so you can resume fast.