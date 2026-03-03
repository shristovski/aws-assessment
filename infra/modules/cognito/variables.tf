variable "email" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}