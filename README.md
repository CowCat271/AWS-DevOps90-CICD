# Multi-Environment CI/CD Deployment Pipeline Project

This repository contains the AWS infrastructure automation scripts for the Multi-Environment CI/CD Deployment Pipeline Project from AWS DevOps 90% by Cloud Native Base Camp.

The project builds a production-ready network and application foundation for the `srv-02` service using AWS CLI automation and launch templates. It supports separate `qc` and `prod` environments with dedicated VPCs, security, auto scaling, load balancing, and Route 53 DNS records.


## Demo

[![Raffle Application Demo](https://img.youtube.com/vi/qz9LUjxudIg/0.jpg)](https://youtu.be/qz9LUjxudIg)


## Repository Scope

This repository includes the AWS shell scripts used to create and manage infrastructure for the `srv-02` deployment:

- `deploy.sh` - Main environment bootstrap wrapper.
- `vpc.sh` - VPC, subnets, route tables, internet gateway.
- `security.sh` - EC2 SSH key creation, Secrets Manager secret, security group rules.
- `autoscalinggroup.sh` - Launch template, network load balancer, target group, listener, and autoscaling group.
- `dns.sh` - Route 53 DNS record creation for the service endpoint.
- `conf-qc.sh`, `conf-prod.sh` - Environment-specific configuration for QC and Production.
- `launch_template/` - EC2 launch template and user data script for instance provisioning.
- `docs/solution-guide.pdf` - Project solution guide.

## How It Works

The deployment flow is designed for two named environments: `qc` and `prod`.

1. Run the main script with environment argument:
   - `./deploy.sh qc`
   - `./deploy.sh prod`

2. `deploy.sh` loads the environment configuration file and sources the helper scripts.
3. `vpc.sh` provisions the VPC, subnets, route tables, and internet access.
4. `security.sh` creates an EC2 key pair, stores it in AWS Secrets Manager, and configures a security group.
5. `autoscalinggroup.sh` provisions the EC2 launch template, NLB, target group, listener, auto scaling group, and scaling policy.
6. `dns.sh` registers the service DNS record in Route 53 using the load balancer DNS target.

## Environment Configuration

The repository contains two environment configuration files:

- `conf-qc.sh` - QC environment settings (example CIDR `10.10.0.0/16`).
- `conf-prod.sh` - Production environment settings (example CIDR `192.168.0.0/16`).

Each configuration file defines:

- `region`
- `network_cidr`
- `public_subnets`
- `private_subnets`
- `dns_name`

## AWS Components Created

- VPC with multiple public/private subnets
- Internet Gateway
- Route Tables and Public Routes
- EC2 Key Pair and Secrets Manager secret
- AWS Security Group for SSH, HTTP, and internal traffic
- EC2 Launch Template with user data for CodeDeploy agent setup
- Network Load Balancer, Target Group, Listener
- Auto Scaling Group with target-tracking CPU scaling policy
- Route 53 DNS record for the service endpoint

## External CI/CD Repository

This project references additional pipeline and YAML files in the companion repository:

- https://github.com/CowCat271/srv-02

That repository contains the CI/CD pipeline definitions, build/ deployment YAMLs, and related service automation for the complete pipeline.

## Prerequisites

- AWS CLI installed and configured with permissions for EC2, VPC, ELB, Auto Scaling, Route 53, Secrets Manager, and IAM.
- A valid AWS account with access to the target region.
- `bash`, `jq`, and standard Linux shell utilities.

## Usage

1. Make the scripts executable if needed:
   - `chmod +x ./deploy.sh ./vpc.sh ./security.sh ./autoscalinggroup.sh ./dns.sh`
2. Execute the deployment for the target environment:
   - `./deploy.sh qc`
   - `./deploy.sh prod`
3. Monitor the output for resource creation progress and any errors.
