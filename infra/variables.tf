variable "email" {
  description = "Your real email address used with recruiting team"
  type        = string
}

variable "repo_url" {
  description = "Your GitHub repo URL, e.g. https://github.com/<user>/aws-assessment"
  type        = string
}

variable "test_user_password" {
  description = "Password to set for the Cognito test user (min 8, uppercase/lowercase/number/symbol recommended)"
  type        = string
  sensitive   = true
}

variable "region_1" {
  type    = string
  default = "us-east-1"
}

variable "region_2" {
  type    = string
  default = "eu-west-1"
}

variable "verification_sns_topic_arn" {
  type    = string
  default = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}