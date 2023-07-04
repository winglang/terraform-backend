# A Terraform Backend written in Wing

The Wing Terraform Backend is an open-source implementation of the Terraform [HTTP](https://developer.hashicorp.com/terraform/language/settings/backends/http) backend, written in the Wing programming language. This backend allows you to store the state of your Terraform project remotely and supports state locking.

## Features

- Remote State Management: Store your Terraform state in a remote, centralized location to enable collaborative workflows.
- State Locking: Avoid state corruption with the built-in state lock and unlock functionality.
- Basic Authentication: Implement a simple user-based authentication to protect your state data.

## Setup

```
npm install -g winglang@latest
npm install
```

## Deployment

Expects valid credentials in ENV

```
wing compile -t tf-aws main.w
```

## Usage

Setup a user in the created DynamoDB Table. e.g.
The create-user-function-name has to be looked up in the AWS console or in the local state file of Terraform. This will be improved.

```
#!/bin/bash

# Execute AWS Lambda function and save the result
result=$(aws lambda invoke \
  --function-name <create-user-function-name> \
  --payload "$(echo -n '{"username":"your-user", "password":"your-password"}' | base64)" \
  --log-type Tail \
  output.txt)

# Parse the "LogResult" field and decode it
log_result=$(echo $result | jq -r '.LogResult' | base64 --decode)

# Display the decoded log result
echo $log_result
```

Define the http backend in Terraform, e.g.

```
terraform {
  backend "http" {
  }
}
```

and run the following to configure it

```
PROJECT_ID="your-project-name"
TF_USERNAME="your-user"
TF_PASSWORD="your-password"
TF_ADDRESS="<api-gateway-url>/<api-gateway-stage>/project/${PROJECT_ID}"

terraform init \
  -backend-config=address=${TF_ADDRESS} \
  -backend-config=lock_address=${TF_ADDRESS}/lock \
  -backend-config=unlock_address=${TF_ADDRESS}/unlock \
  -backend-config=username=${TF_USERNAME} \
  -backend-config=password=${TF_PASSWORD} \
  -backend-config=lock_method=POST \
  -backend-config=unlock_method=POST \
  -backend-config=retry_wait_min=5
```

## Roadmap

- [ ] Serious credential handling
- [ ] More tests
- [ ] A plugin to tune the bucket settings (i.e. versioning)
- [ ] CI / CD via Github Actions
- [ ] Easier user / token handling
- [ ] Support multiple branches per state
- [ ] Logs
- [ ] Monitoring
- [ ] Azure (missing SDK resources)
- [ ] GCP (missing SDK resources)
- [ ] Authorization (?)
- [ ] A simple Web UI
- [ ] Wing Github Action Integration