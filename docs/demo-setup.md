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

Create a GitHub App on your account (Settings → Developer settings → GitHub Apps):

- Name: anything, for example `dac-demo-runners`.
- Webhook: uncheck "Active".
- Repository permissions: **Actions: Read and write**, **Administration: Read and write**,
  **Metadata: Read-only**, **Contents: Read-only** (Contents is for Argo CD while the repo
  is private; drop it once the repo is public).
- After creating: note the **App ID**, generate and download a **private key**.
- Install the app on your fork only. The installation ID is the number at the end of
  the installation URL (`.../settings/installations/<id>`).

## 3. Create the cluster (`infra/01-cluster`)

    cd infra/01-cluster
    cp terraform.tfvars.example terraform.tfvars   # optional, defaults are fine
    terraform init -backend-config=backend.hcl
    terraform apply

Takes about 5 minutes. The cluster is tagged `donotdelete`; some accounts run
nightly cleanup jobs that honour this tag.

## 4. Bootstrap Argo CD (`infra/02-bootstrap`)

    cd infra/02-bootstrap
    cp terraform.tfvars.example terraform.tfvars   # fill in the GitHub App values
    terraform init -backend-config=backend.hcl
    terraform apply

This installs Argo CD, writes the secrets and creates the root Application. Argo CD
then syncs everything under `gitops/`. Before the first apply, point `gitops/root/*.yaml`
at your fork:

    sed -i 's#github.com/slashben/#github.com/<you>/#' gitops/root/*.yaml gitops/values/arc-runners.yaml

and commit that change to your fork's `main`.

## 5. Verify

## Local validation with kind

    ./hack/kind-up.sh
    kubectl -n argocd get applications -w

Expect `kubescape`, `monitoring`, `arc-controller`, `monitoring-config` and `rules` to
reach `Synced / Healthy` within about 5 minutes. `arc-runners` needs real GitHub App
credentials; pass them as `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID` and
`GITHUB_APP_PRIVATE_KEY_FILE`. The repo must be reachable by Argo CD: while it is
private, the same GitHub App needs the Contents permission.

## Troubleshooting
