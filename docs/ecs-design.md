# ECS Deployment Design for MCP Toolbox and Agent

## Overview

This document describes the architecture and deployment strategy for running the MCP Toolbox server and Python agent on AWS ECS with Fargate.

---

## Architecture

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                        AWS Cloud                            │
                                    │                                                             │
┌──────────┐     HTTPS              │  ┌─────────────────────────────────────────────────────┐   │
│  Users   │◀────────────────────────▶│           Application Load Balancer                  │   │
└──────────┘                        │  │              (Public Subnet)                         │   │
                                    │  └─────────────────────┬───────────────────────────────┘   │
                                    │                        │                                   │
                                    │  ┌─────────────────────▼───────────────────────────────┐   │
                                    │  │                     VPC                              │   │
                                    │  │                                                      │   │
                                    │  │   ┌─────────────────────────────────────────────┐   │   │
                                    │  │   │            ECS Cluster (Fargate)            │   │   │
                                    │  │   │              (Private Subnet)               │   │   │
                                    │  │   │                                             │   │   │
                                    │  │   │   ┌─────────────────┐  ┌─────────────────┐  │   │   │
                                    │  │   │   │  Agent Service  │  │ Toolbox Service │  │   │   │
                                    │  │   │   │                 │  │                 │  │   │   │
                                    │  │   │   │  ┌───────────┐  │  │  ┌───────────┐  │  │   │   │
                                    │  │   │   │  │   Task    │  │  │  │   Task    │  │  │   │   │
                                    │  │   │   │  │ (Fargate) │──┼──┼─▶│ (Fargate) │  │  │   │   │
                                    │  │   │   │  └───────────┘  │  │  └───────────┘  │  │   │   │
                                    │  │   │   │                 │  │                 │  │   │   │
                                    │  │   │   └─────────────────┘  └────────┬────────┘  │   │   │
                                    │  │   │                                 │           │   │   │
                                    │  │   └─────────────────────────────────┼───────────┘   │   │
                                    │  │                                     │               │   │
                                    │  └─────────────────────────────────────┼───────────────┘   │
                                    │                                        │                   │
                                    │  ┌──────────────────┐  ┌──────────────▼────────────────┐  │
                                    │  │ Secrets Manager  │  │         RDS / Database        │  │
                                    │  │   - DB creds     │  │        (Private Subnet)       │  │
                                    │  │   - AWS keys     │  └───────────────────────────────┘  │
                                    │  └──────────────────┘                                     │
                                    │                                                           │
                                    │  ┌──────────────────┐  ┌───────────────────────────────┐  │
                                    │  │    CloudWatch    │  │             ECR               │  │
                                    │  │   Logs/Metrics   │  │   Container Image Registry    │  │
                                    │  └──────────────────┘  └───────────────────────────────┘  │
                                    │                                                           │
                                    └───────────────────────────────────────────────────────────┘
                                                               │
                                                               ▼
                                                    ┌───────────────────┐
                                                    │  Amazon Bedrock   │
                                                    │     (Claude)      │
                                                    └───────────────────┘
```

---

## Components

### 1. VPC Configuration

| Component | Configuration |
|-----------|---------------|
| VPC CIDR | `10.0.0.0/16` |
| Public Subnets | `10.0.1.0/24`, `10.0.2.0/24` (2 AZs) |
| Private Subnets | `10.0.10.0/24`, `10.0.20.0/24` (2 AZs) |
| NAT Gateway | 1 per AZ for high availability |
| VPC Endpoints | ECR, Secrets Manager, CloudWatch Logs, Bedrock |

### 2. ECS Cluster

- **Launch Type**: Fargate (serverless)
- **Cluster Name**: `mcp-cluster`
- **Capacity Providers**: `FARGATE` and `FARGATE_SPOT` (for cost optimization)

### 3. Container Images (ECR)

| Repository | Image | Description |
|------------|-------|-------------|
| `mcp-toolbox` | Based on Google's toolbox image | MCP server with database tools |
| `mcp-agent` | Custom Python image | Bedrock-connected agent |

### 4. ECS Services

#### Toolbox Service

```yaml
Service Name: mcp-toolbox-service
Task Definition: mcp-toolbox-task
Desired Count: 2  # For high availability
Launch Type: FARGATE
Network Mode: awsvpc

Task Resources:
  CPU: 512 (0.5 vCPU)
  Memory: 1024 MB

Container:
  Name: toolbox
  Port: 5000
  Health Check: /health

Service Discovery:
  Namespace: mcp.local
  Service: toolbox
  DNS: toolbox.mcp.local
```

#### Agent Service

```yaml
Service Name: mcp-agent-service
Task Definition: mcp-agent-task
Desired Count: 2
Launch Type: FARGATE
Network Mode: awsvpc

Task Resources:
  CPU: 1024 (1 vCPU)
  Memory: 2048 MB

Container:
  Name: agent
  Port: 8080  # If exposing HTTP API

Environment:
  MCP_URL: http://toolbox.mcp.local:5000/mcp/sse
```

---

## Security Configuration

### IAM Roles

#### Task Execution Role
Allows ECS to pull images and write logs.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/ecs/mcp-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:mcp/*"
    }
  ]
}
```

#### Agent Task Role
Allows the agent to invoke Bedrock.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/anthropic.claude-*"
    }
  ]
}
```

### Security Groups

#### ALB Security Group
```
Inbound:  443 (HTTPS) from 0.0.0.0/0
Outbound: All to VPC CIDR
```

#### Toolbox Service Security Group
```
Inbound:  5000 from Agent Security Group
Inbound:  5000 from ALB Security Group (for health checks)
Outbound: 1433/5432 to Database Security Group
```

#### Agent Service Security Group
```
Inbound:  8080 from ALB Security Group
Outbound: 5000 to Toolbox Security Group
Outbound: 443 to Bedrock VPC Endpoint
```

### Secrets Management

Store credentials in AWS Secrets Manager:

| Secret Path | Contents |
|-------------|----------|
| `mcp/database/mssql` | `{"username": "...", "password": "..."}` |
| `mcp/database/postgres` | `{"username": "...", "password": "..."}` |

Reference in task definition:
```json
{
  "secrets": [
    {
      "name": "MSSQL_USER",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:mcp/database/mssql:username::"
    },
    {
      "name": "MSSQL_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:mcp/database/mssql:password::"
    }
  ]
}
```

---

## Service Discovery

Use AWS Cloud Map for service-to-service communication:

```yaml
Namespace: mcp.local (Private DNS)

Services:
  - toolbox.mcp.local -> Toolbox ECS Service
  - agent.mcp.local   -> Agent ECS Service
```

The agent connects to the toolbox via: `http://toolbox.mcp.local:5000/mcp/sse`

---

## Load Balancer Configuration

### Application Load Balancer

```yaml
Name: mcp-alb
Scheme: internet-facing
Type: application

Listeners:
  - Port: 443
    Protocol: HTTPS
    Certificate: ACM certificate for your domain
    Default Action: Forward to agent-target-group

Target Groups:
  - Name: agent-target-group
    Protocol: HTTP
    Port: 8080
    Health Check: /health
    Targets: Agent ECS Service

  - Name: toolbox-target-group (optional, for debugging)
    Protocol: HTTP
    Port: 5000
    Health Check: /health
    Targets: Toolbox ECS Service
```

---

## Deployment Strategy

### CI/CD Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   GitHub    │───▶│  CodeBuild  │───▶│     ECR     │───▶│    ECS      │
│   (Source)  │    │  (Build)    │    │   (Store)   │    │  (Deploy)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### Deployment Configuration

```yaml
Deployment Type: Rolling Update
Minimum Healthy Percent: 50
Maximum Percent: 200

Health Check Grace Period: 60 seconds
Deregistration Delay: 30 seconds
```

### Blue/Green Deployment (Optional)

For zero-downtime deployments, use CodeDeploy with ECS:

```yaml
Deployment Controller: CODE_DEPLOY
Deployment Configuration: CodeDeployDefault.ECSAllAtOnce

Traffic Shifting:
  - Type: AllAtOnce  # or TimeBasedLinear, TimeBasedCanary
```

---

## Monitoring and Logging

### CloudWatch Logs

```yaml
Log Groups:
  - /ecs/mcp-toolbox
  - /ecs/mcp-agent

Retention: 30 days
```

### CloudWatch Metrics

| Metric | Service | Alarm Threshold |
|--------|---------|-----------------|
| CPUUtilization | Both | > 80% |
| MemoryUtilization | Both | > 80% |
| HealthyHostCount | ALB Target | < 1 |
| HTTPCode_Target_5XX | ALB | > 10/minute |

### Container Insights

Enable Container Insights for the cluster:
```bash
aws ecs update-cluster-settings \
  --cluster mcp-cluster \
  --settings name=containerInsights,value=enabled
```

---

## Auto Scaling

### Target Tracking Scaling

```yaml
Toolbox Service:
  Min Capacity: 2
  Max Capacity: 10
  Target CPU Utilization: 70%
  Scale-in Cooldown: 300s
  Scale-out Cooldown: 60s

Agent Service:
  Min Capacity: 2
  Max Capacity: 20
  Target CPU Utilization: 70%
  Target Request Count: 1000 per target
```

---

## Cost Estimation

### Monthly Costs (Small Production Deployment)

| Resource | Configuration | Estimated Cost |
|----------|---------------|----------------|
| ECS Fargate - Toolbox | 2 tasks × 0.5 vCPU × 1 GB | ~$30 |
| ECS Fargate - Agent | 2 tasks × 1 vCPU × 2 GB | ~$60 |
| Application Load Balancer | 1 ALB + LCUs | ~$25 |
| NAT Gateway | 2 (for HA) | ~$65 |
| CloudWatch Logs | 10 GB/month | ~$5 |
| Secrets Manager | 4 secrets | ~$2 |
| ECR | 5 GB storage | ~$1 |
| VPC Endpoints | 4 endpoints | ~$30 |
| **Total** | | **~$220/month** |

### Cost Optimization Tips

1. **Use Fargate Spot** for non-critical workloads (up to 70% savings)
2. **Right-size tasks** based on actual usage metrics
3. **Use a single NAT Gateway** if HA is not critical
4. **Reduce VPC Endpoints** by using NAT for some services
5. **Set log retention** to appropriate periods

---

## Terraform Module Structure

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
│
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ecs-cluster/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ecs-service/
│   │   ├── main.tf          # Generic service module
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── alb/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── secrets/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/
    ├── dev/
    │   ├── main.tf
    │   └── terraform.tfvars
    └── prod/
        ├── main.tf
        └── terraform.tfvars
```

---

## Deployment Steps

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.5.0 installed
3. Docker/Podman for building images
4. Domain name with ACM certificate

### Step-by-Step Deployment

```bash
# 1. Build and push container images
cd python-agent
podman build -t mcp-agent -f Containerfile .
podman tag mcp-agent:latest ${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/mcp-agent:latest
podman push ${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/mcp-agent:latest

# 2. Create secrets in Secrets Manager
aws secretsmanager create-secret \
  --name mcp/database/mssql \
  --secret-string '{"username":"myuser","password":"mypassword"}'

# 3. Deploy infrastructure with Terraform
cd terraform/environments/prod
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Verify deployment
aws ecs list-services --cluster mcp-cluster
aws ecs describe-services --cluster mcp-cluster --services mcp-toolbox-service mcp-agent-service
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Task fails to start | Image pull error | Check ECR permissions and image exists |
| Agent can't reach Toolbox | Service discovery issue | Verify Cloud Map namespace and DNS |
| Connection refused | Security group rules | Check inbound rules allow traffic |
| Secrets not available | IAM permissions | Verify task execution role has secretsmanager:GetSecretValue |
| Bedrock access denied | Missing permissions | Add bedrock:InvokeModel to task role |

### Debugging Commands

```bash
# View task logs
aws logs tail /ecs/mcp-agent --follow

# Describe task failures
aws ecs describe-tasks --cluster mcp-cluster --tasks <task-arn>

# Test service discovery
aws servicediscovery discover-instances \
  --namespace-name mcp.local \
  --service-name toolbox

# Execute command in running container
aws ecs execute-command \
  --cluster mcp-cluster \
  --task <task-arn> \
  --container agent \
  --interactive \
  --command "/bin/sh"
```

---

## Next Steps

1. **Implement Terraform modules** for infrastructure as code
2. **Set up CI/CD pipeline** with GitHub Actions or CodePipeline
3. **Configure WAF** for ALB to protect against common attacks
4. **Implement request tracing** with X-Ray
5. **Set up alerting** with SNS for critical metrics
