# A Terraform Backend written in Wing

The Wing Terraform Backend is an open-source implementation of the Terraform [HTTP](https://developer.hashicorp.com/terraform/language/settings/backends/http) backend, written in the Wing programming language. This backend allows you to store the state of your Terraform project remotely and supports state locking.

## Features

- Remote State Management: Store your Terraform state in a remote, centralized location to enable collaborative workflows.
- State Locking: Avoid state corruption with the built-in state lock and unlock functionality.
- Basic Authentication: Implement a simple user-based authentication to protect your state data.

Still WIP and likely blocked by https://github.com/winglang/wing/issues/2889 for AWS deployments