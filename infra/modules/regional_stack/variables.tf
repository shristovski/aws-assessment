variable "region" { type = string }

variable "email" { type = string }
variable "repo_url" { type = string }

variable "cognito_user_pool_arn" { type = string }
variable "cognito_user_pool_client_id" { type = string }

variable "verification_sns_topic_arn" { type = string }