data "aws_region" "current" {}

locals {
  name_prefix = "unleash-${var.region}"
  sns_region  = split(":", var.verification_sns_topic_arn)[3]
}

############################
# VPC (public subnets only)
############################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${local.name_prefix}-rt-public" }
}

# checkov:skip=CKV_AWS_130: Public subnets required to avoid NAT Gateway charges per assessment requirements
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = { Name = "${local.name_prefix}-subnet-public-a" }
}

# checkov:skip=CKV_AWS_130: Public subnets required to avoid NAT Gateway charges per assessment requirements
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}b"
  tags                    = { Name = "${local.name_prefix}-subnet-public-b" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs_task" {
  name        = "${local.name_prefix}-ecs-task-sg"
  description = "ECS task security group (outbound HTTPS only)"
  vpc_id      = aws_vpc.this.id

  # Restrict outbound to HTTPS only (SNS publish, AWS APIs)
  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# KMS key (regional) for DynamoDB encryption (CMK)
############################
resource "aws_kms_key" "ddb" {
  description             = "KMS CMK for DynamoDB table encryption (${local.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "ddb" {
  name          = "alias/${local.name_prefix}-ddb"
  target_key_id = aws_kms_key.ddb.key_id
}

############################
# DynamoDB (regional)
############################
resource "aws_dynamodb_table" "greeting_logs" {
  name         = "${local.name_prefix}-GreetingLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # Enable PITR (backup)
  point_in_time_recovery {
    enabled = true
  }

  # Use customer-managed CMK
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.ddb.arn
  }
}

############################
# Greeter Lambda
############################
data "archive_file" "greeter_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/greeter"
  output_path = "${path.module}/greeter.zip"
}

resource "aws_iam_role" "greeter_role" {
  name = "${local.name_prefix}-greeter-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "greeter_basic" {
  role       = aws_iam_role.greeter_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "greeter_policy" {
  name = "${local.name_prefix}-greeter-policy"
  role = aws_iam_role.greeter_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["dynamodb:PutItem"],
        Resource = aws_dynamodb_table.greeting_logs.arn
      },
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = var.verification_sns_topic_arn
      }
    ]
  })
}

# checkov:skip=CKV_AWS_117: Lambda intentionally not placed in VPC to avoid NAT (SNS/Dynamo public endpoints needed for assessment)
# checkov:skip=CKV_AWS_116: DLQ omitted for short-lived assessment functions
# checkov:skip=CKV_AWS_272: Code signing validation out of scope for assessment
# checkov:skip=CKV_AWS_50: X-Ray tracing optional/out of scope for this assessment
resource "aws_lambda_function" "greeter" {
  function_name = "${local.name_prefix}-greeter"
  role          = aws_iam_role.greeter_role.arn
  runtime       = "python3.12"
  handler       = "app.handler"

  filename         = data.archive_file.greeter_zip.output_path
  source_code_hash = data.archive_file.greeter_zip.output_base64sha256

  environment {
    variables = {
      DDB_TABLE          = aws_dynamodb_table.greeting_logs.name
      SNS_TOPIC_ARN      = var.verification_sns_topic_arn
      EMAIL              = var.email
      REPO_URL           = var.repo_url
        EXEC_REGION        = var.region
      SNS_PUBLISH_REGION = local.sns_region
    }
  }
}

resource "aws_cloudwatch_log_group" "greeter" {
  name              = "/aws/lambda/${aws_lambda_function.greeter.function_name}"
  retention_in_days = 7
}

############################
# ECS Cluster + Task
############################
resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.name_prefix}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_publish" {
  name = "${local.name_prefix}-ecs-task-publish"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["sns:Publish"],
      Resource = var.verification_sns_topic_arn
    }]
  })
}

resource "aws_ecs_task_definition" "publisher" {
  family                   = "${local.name_prefix}-publisher"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "awscli"
    image = "amazon/aws-cli:2.15.41"

    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }

    command = [
      "sh", "-lc",
      "aws sns publish --region ${local.sns_region} --topic-arn ${var.verification_sns_topic_arn} --message '{\"email\":\"${var.email}\",\"source\":\"ECS\",\"region\":\"${var.region}\",\"repo\":\"${var.repo_url}\"}' && echo done"
    ]
  }])
}

############################
# Dispatcher Lambda (runs ECS task)
############################
data "archive_file" "dispatcher_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/dispatcher"
  output_path = "${path.module}/dispatcher.zip"
}

resource "aws_iam_role" "dispatcher_role" {
  name = "${local.name_prefix}-dispatcher-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dispatcher_basic" {
  role       = aws_iam_role.dispatcher_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dispatcher_policy" {
  name = "${local.name_prefix}-dispatcher-policy"
  role = aws_iam_role.dispatcher_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ecs:RunTask"],
        Resource = [aws_ecs_task_definition.publisher.arn]
      },
      {
        Effect   = "Allow",
        Action   = ["ecs:DescribeTasks", "ecs:DescribeTaskDefinition", "ecs:DescribeClusters"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.ecs_execution_role.arn,
          aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
  })
}

# checkov:skip=CKV_AWS_117: Lambda intentionally not placed in VPC to avoid NAT (SNS/Dynamo public endpoints needed for assessment)
# checkov:skip=CKV_AWS_116: DLQ omitted for short-lived assessment functions
# checkov:skip=CKV_AWS_272: Code signing validation out of scope for assessment
# checkov:skip=CKV_AWS_50: X-Ray tracing optional/out of scope for this assessment
resource "aws_lambda_function" "dispatcher" {
  function_name = "${local.name_prefix}-dispatcher"
  role          = aws_iam_role.dispatcher_role.arn
  runtime       = "python3.12"
  handler       = "app.handler"

  filename         = data.archive_file.dispatcher_zip.output_path
  source_code_hash = data.archive_file.dispatcher_zip.output_base64sha256

  environment {
    variables = {
      EXEC_REGION  = var.region
      CLUSTER_ARN  = aws_ecs_cluster.this.arn
      TASK_DEF_ARN = aws_ecs_task_definition.publisher.arn
      SUBNETS      = join(",", [aws_subnet.public_a.id, aws_subnet.public_b.id])
      SECURITY_GRP = aws_security_group.ecs_task.id
    }
  }
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${aws_lambda_function.dispatcher.function_name}"
  retention_in_days = 7
}

############################
# API Gateway HTTP API + JWT authorizer (Cognito)
############################
resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-jwt-auth"

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${split("/", var.cognito_user_pool_arn)[1]}"
  }
}

resource "aws_apigatewayv2_integration" "greet" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatch" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "greet" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /greet"
  target             = "integrations/${aws_apigatewayv2_integration.greet.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /dispatch"
  target             = "integrations/${aws_apigatewayv2_integration.dispatch.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw_greet" {
  statement_id  = "AllowAPIGatewayInvokeGreet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigw_dispatch" {
  statement_id  = "AllowAPIGatewayInvokeDispatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}