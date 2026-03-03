# Unleash Live – AWS Assessment (Terraform)

This repo provisions:
- Cognito User Pool + Client in **us-east-1**
- A **multi-region** identical stack in **us-east-1** and **eu-west-1**:
  - API Gateway HTTP API with JWT authorizer (Cognito)
  - DynamoDB regional table
  - Lambda Greeter (/greet): writes to DynamoDB and publishes verification payload to SNS
  - Lambda Dispatcher (/dispatch): runs a Fargate task
  - ECS Fargate task: publishes verification payload to SNS and exits
- An automated test script that:
  1) authenticates against Cognito to get a JWT
  2) concurrently calls /greet in both regions (latency measured)
  3) concurrently calls /dispatch in both regions

## Prereqs
- Terraform >= 1.6
- AWS CLI configured for your sandbox account
- Python 3.10+ for test script

## Configure
Set these values (examples):
- `email`: email address
- `repo_url`: https://github.com/user/aws-assessment
- `test_user_password`: password you will use to authenticate

## Deploy
```bash
cd infra

terraform init

# PowerShell example
terraform apply `
  -var="email=your_email@example.com" `
  -var="repo_url=https://github.com/<user>/aws-assessment" `
  -var="test_user_password=YourPassw0rd!" `
  -auto-approve