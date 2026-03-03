resource "aws_cognito_user_pool" "this" {
  name = "unleash-assessment-user-pool"

  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "unleash-assessment-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]
}

# Create user (required by assignment)
resource "aws_cognito_user" "test" {
  user_pool_id = aws_cognito_user_pool.this.id
  username     = var.email

  attributes = {
    email          = var.email
    email_verified = "true"
  }

  # Create without sending email
  message_action     = "SUPPRESS"
  temporary_password = "TempPassw0rd!234" # will be immediately overridden
}

# Set a permanent password so tests can authenticate without NEW_PASSWORD_REQUIRED
resource "null_resource" "set_password" {
  triggers = {
    user_pool_id = aws_cognito_user_pool.this.id
    username     = var.email
  }

  provisioner "local-exec" {
    command = "aws cognito-idp admin-set-user-password --region us-east-1 --user-pool-id ${aws_cognito_user_pool.this.id} --username \"${var.email}\" --password \"${var.password}\" --permanent"
  }

  depends_on = [aws_cognito_user.test]
}