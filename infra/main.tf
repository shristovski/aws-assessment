provider "aws" {
  region = var.region_1
}

provider "aws" {
  alias  = "r2"
  region = var.region_2
}

data "aws_caller_identity" "current" {}

module "cognito" {
  source    = "./modules/cognito"
  providers = { aws = aws }
  email     = var.email
  password  = var.test_user_password
}

module "stack_r1" {
  source    = "./modules/regional_stack"
  providers = { aws = aws }

  region                      = var.region_1
  email                       = var.email
  repo_url                    = var.repo_url
  cognito_user_pool_arn       = module.cognito.user_pool_arn
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
  verification_sns_topic_arn  = var.verification_sns_topic_arn
}

module "stack_r2" {
  source    = "./modules/regional_stack"
  providers = { aws = aws.r2 }

  region                      = var.region_2
  email                       = var.email
  repo_url                    = var.repo_url
  cognito_user_pool_arn       = module.cognito.user_pool_arn
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
  verification_sns_topic_arn  = var.verification_sns_topic_arn
}