output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "api_r1_base_url" {
  value = module.stack_r1.api_base_url
}

output "api_r2_base_url" {
  value = module.stack_r2.api_base_url
}