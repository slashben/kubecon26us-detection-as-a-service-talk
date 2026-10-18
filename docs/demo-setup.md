# Demo setup

How to bring up the demo cluster from this repo. Filled in section by section as the
infrastructure lands.

## Prerequisites

- `doctl` authenticated (`doctl auth init`) and `DIGITALOCEAN_TOKEN` exported.
- A DigitalOcean Spaces key pair, exported as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
- `terraform` >= 1.6, `kubectl`, `helm` >= 3.14.
- A fork of this repository (the runners register against your fork).

## 1. Terraform state bucket

Create one Spaces bucket (any region) in the DigitalOcean console or with the AWS CLI:

    aws --endpoint-url https://ams3.digitaloceanspaces.com s3 mb s3://my-dac-demo-tfstate

Then in both `infra/01-cluster` and `infra/02-bootstrap`:

    cp backend.hcl.example backend.hcl   # edit bucket and endpoint

## 2. GitHub App

## 3. Create the cluster (`infra/01-cluster`)

    cd infra/01-cluster
    cp terraform.tfvars.example terraform.tfvars   # optional, defaults are fine
    terraform init -backend-config=backend.hcl
    terraform apply

Takes about 5 minutes. The cluster is tagged `donotdelete`; some accounts run
nightly cleanup jobs that honour this tag.

## 4. Bootstrap Argo CD (`infra/02-bootstrap`)

## 5. Verify

## Local validation with kind

## Troubleshooting
