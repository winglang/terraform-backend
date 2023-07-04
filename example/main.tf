provider "null" {}
terraform {
  backend "http" {
  }
}

resource "null_resource" "hello" {
  provisioner "local-exec" {
    command = "echo Hello, World!"
  }
}
