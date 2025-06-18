# terraform-assignment
PoC for Basic Terraform in AWS

# Summary
The next terraform code creates a PoC for nginxdemos/hello in a Docker container on AWS. A new Virtual Private Cloud (VPC), including public and private subnets, route tables, and internet gateways (IGW and NAT GW). Also ALB, Autoscaling Groups, Launch Template with a user_data that creates hte Docker container are created with the terraform code.

The code was created to be executed in CLI.


# Setting up the AWS configuration
Make sure that AWS authentication and authorization has been configured either in AWS_CREDENTIALS or AWS_CONFIG. 


# Execute terraform commands 
Make sure that terraform has been properly configured.

Use the next commands to initialize, plan and later apply the terraform changes

1. Use `terraform init` to initilize terraform for the code in this directory
2. Use `teraform plan` to validate the changes. If a previous AWS key-pair exists, it can be included here or a default one will be created
3. Use `terraform apply` to make effective the changes. 
