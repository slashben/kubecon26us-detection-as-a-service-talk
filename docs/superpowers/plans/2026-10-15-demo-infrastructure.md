# Demo Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the DOKS cluster, Argo CD app-of-apps, Kubescape, Alertmanager and ARC runner infrastructure for the talk demo, validated on kind, with DigitalOcean apply left as a separate, explicitly requested step.

**Architecture:** Two Terraform stacks own what Git cannot hold (cluster, Argo CD, secrets). Argo CD syncs six child Applications from `gitops/` in this repo: Kubescape, kube-prometheus-stack, ARC controller, ARC runner scale set, Alertmanager routing and the Rules objects. A kind script reproduces the bootstrap locally with the same GitOps tree.

**Tech Stack:** Terraform 1.16, providers `digitalocean/digitalocean ~> 2.0`, `hashicorp/kubernetes ~> 2.0`, `hashicorp/helm ~> 3.0`; Argo CD chart `argo/argo-cd 10.10.5`, `argo/argocd-apps 2.0.6`; `kubescape/kubescape-operator 1.40.5`; `prometheus-community/kube-prometheus-stack 92.8.0`; ARC charts `0.15.0` from `ghcr.io/actions/actions-runner-controller-charts`; kind v0.29.0; GitHub Actions with `actions/checkout` and `aquasecurity/trivy-action` pinned by SHA.

**Spec:** `docs/superpowers/specs/2026-10-15-demo-infrastructure-design.md`

## Global Constraints

- The repo will be published: no secrets, no internal URLs, no account-specific values committed. Secrets come only from gitignored `terraform.tfvars` or environment variables.
- Terraform state is DigitalOcean Spaces via the `s3` backend; bucket and endpoint come from a gitignored `backend.hcl`, with a committed `backend.hcl.example`.
- The DOKS cluster and its node pool carry the tag `donotdelete`.
- Node pool: 3 nodes of `s-4vcpu-8gb`, region default `nyc3`, cluster name default `dac-demo`.
- Every chart version and action ref is pinned to the exact values listed in Tech Stack.
- Runner scale set name is `dac-runners`; runner pods carry labels `app.kubernetes.io/name: dac-runner` and `dac.kubescape.io/role: ci-runner`; namespace `arc-runners`.
- The Alertmanager route keys on `alertname = KubescapeRuleViolated` and `namespace = arc-runners`.
- Commits use `git commit -s` (Signed-off-by, repo convention) and no AI attribution lines (user's global CLAUDE.md).
- The repo has a `docs/` folder: a task that adds behavior updates `docs/demo-setup.md` or `README.md` in the same commit.
- Shell commands that read upstream values files or grep must go through `rtk proxy` when the hook truncates output (observed in planning: `helm show values` came back cut to 41 lines without it).

## Review Focus

1. An attendee runs `terraform init` with a `backend.hcl` whose endpoint region differs from `region` in tfvars. Expected: state still works, because the backend endpoint is independent of the cluster region. Pinned by Task 2 step 6 (validate with a non-nyc3 endpoint in the example file).
2. `slack_webhook_url` left empty. Expected: Slack route exists, delivery fails quietly, the rest is unaffected. Pinned by Task 3 step 7 (plan with empty webhook shows a placeholder secret value).
3. A `Rules` object with a CEL syntax error is merged. Expected: Argo CD syncs it (the CRD schema does not validate CEL), node-agent logs the rejection, other rules stay active. Not pinned by infrastructure tests; recorded for the rule-authoring work that follows this plan.
4. `kube-prometheus-stack` CRDs exceed the client-side apply annotation limit. Expected: the monitoring Application syncs anyway. Pinned by Task 4 step 2 (`ServerSideApply=true` on that Application) and Task 8 (kind run shows it Synced).
5. The AlertmanagerConfig lives in `monitoring` while alerts carry `namespace = arc-runners`. Expected: the Slack route still matches. Pinned by Task 4 step 4 (`alertmanagerConfigMatcherStrategy.type: None`) and Task 8 step 6 (`amtool config routes test`).

---

### Task 1: Repo hygiene and ignore rules

**Files:**
- Modify: `.gitignore` (replace the Python template with repo-specific rules)
- Create: `docs/demo-setup.md` (skeleton; later tasks fill sections)

**Interfaces:**
- Produces: ignore rules every later task relies on (`terraform.tfvars`, `backend.hcl`, `.terraform/`, `*.tfstate*`, `kubeconfig*`, `*.pem`).

- [ ] **Step 1: Replace `.gitignore`**

```gitignore
# Terraform
**/.terraform/
**/.terraform.lock.hcl
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
backend.hcl
crash.log

# Kubernetes / local clusters
kubeconfig*
*.kubeconfig

# Secrets
*.pem
*.key

# Editors
.vscode/
.idea/
*.swp
```

Note: `.terraform.lock.hcl` is ignored on purpose. The demo is rerun on different OSes by attendees and a lock pinned to one platform's provider hashes is a support burden; the version constraints in `versions.tf` are the pin.

- [ ] **Step 2: Create the runbook skeleton**

```markdown
# Demo setup

How to bring up the demo cluster from this repo. Filled in section by section as the
infrastructure lands.

## Prerequisites

## 1. Terraform state bucket

## 2. GitHub App

## 3. Create the cluster (`infra/01-cluster`)

## 4. Bootstrap Argo CD (`infra/02-bootstrap`)

## 5. Verify

## Local validation with kind

## Troubleshooting
```

- [ ] **Step 3: Verify the ignore rules**

Run: `cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk && touch infra-probe.tfvars backend.hcl && git check-ignore -v infra-probe.tfvars backend.hcl; rm infra-probe.tfvars backend.hcl`
Expected: both paths printed as ignored.

- [ ] **Step 4: Commit**

```bash
git add .gitignore docs/demo-setup.md
git commit -s -m "Replace Python gitignore with Terraform/Kubernetes rules, add runbook skeleton"
```

---

### Task 2: Terraform stack `infra/01-cluster`

**Files:**
- Create: `infra/01-cluster/versions.tf`
- Create: `infra/01-cluster/backend.tf`
- Create: `infra/01-cluster/backend.hcl.example`
- Create: `infra/01-cluster/variables.tf`
- Create: `infra/01-cluster/main.tf`
- Create: `infra/01-cluster/outputs.tf`
- Create: `infra/01-cluster/terraform.tfvars.example`
- Modify: `docs/demo-setup.md` (sections 1 and 3)

**Interfaces:**
- Produces: a DOKS cluster named `var.cluster_name` (default `dac-demo`) that Task 3 looks up by name. Output `cluster_name`, `cluster_id`.

- [ ] **Step 1: `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

provider "digitalocean" {
  # DIGITALOCEAN_TOKEN is read from the environment.
}
```

- [ ] **Step 2: `backend.tf` and `backend.hcl.example`**

`backend.tf`:

```hcl
terraform {
  backend "s3" {
    # bucket and endpoints come from backend.hcl (gitignored):
    #   terraform init -backend-config=backend.hcl
    key    = "01-cluster/terraform.tfstate"
    region = "us-east-1"

    # DigitalOcean Spaces is S3-compatible but is not AWS.
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = false
  }
}
```

`backend.hcl.example`:

```hcl
# Copy to backend.hcl and edit. backend.hcl is gitignored.
# Credentials: export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY set to a Spaces key pair.
bucket = "my-dac-demo-tfstate"
endpoints = {
  s3 = "https://ams3.digitaloceanspaces.com"
}
```

The example deliberately uses `ams3`, not the cluster's default `nyc3`, to show the two are independent (Review Focus 1).

- [ ] **Step 3: `variables.tf`**

```hcl
variable "cluster_name" {
  description = "DOKS cluster name. 02-bootstrap looks the cluster up by this name."
  type        = string
  default     = "dac-demo"
}

variable "region" {
  description = "DigitalOcean region slug for the VPC and cluster."
  type        = string
  default     = "nyc3"
}

variable "kubernetes_version_prefix" {
  description = "Minor version prefix; the latest DOKS patch release matching it is used."
  type        = string
  default     = "1.36."
}

variable "node_size" {
  description = "Droplet size slug for the node pool."
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "node_count" {
  description = "Number of nodes in the default pool."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags applied to the cluster and node pool. 'donotdelete' keeps the cluster out of the account's nightly cleanup."
  type        = list(string)
  default     = ["donotdelete", "dac-demo"]
}
```

- [ ] **Step 4: `main.tf` and `outputs.tf`**

`main.tf`:

```hcl
data "digitalocean_kubernetes_versions" "selected" {
  version_prefix = var.kubernetes_version_prefix
}

resource "digitalocean_vpc" "demo" {
  name   = "${var.cluster_name}-vpc"
  region = var.region
}

resource "digitalocean_kubernetes_cluster" "demo" {
  name     = var.cluster_name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.selected.latest_version
  vpc_uuid = digitalocean_vpc.demo.id
  tags     = var.tags

  node_pool {
    name       = "default"
    size       = var.node_size
    node_count = var.node_count
    tags       = var.tags
  }
}
```

`outputs.tf`:

```hcl
output "cluster_name" {
  value = digitalocean_kubernetes_cluster.demo.name
}

output "cluster_id" {
  value = digitalocean_kubernetes_cluster.demo.id
}

output "kubernetes_version" {
  value = digitalocean_kubernetes_cluster.demo.version
}
```

`terraform.tfvars.example`:

```hcl
cluster_name = "dac-demo"
region       = "nyc3"
```

- [ ] **Step 5: Validate**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk/infra/01-cluster
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```
Expected: `fmt` prints nothing, `validate` prints `Success! The configuration is valid.`

- [ ] **Step 6: Validate the backend example parses**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk/infra/01-cluster
AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x terraform init -backend-config=backend.hcl.example -input=false 2>&1 | head -20
rm -rf .terraform
```
Expected: init proceeds past backend parsing and fails only on reaching the bucket (a network or 403 error naming `ams3.digitaloceanspaces.com`). A parse error about `endpoints` would mean the example is wrong.

- [ ] **Step 7: Fill runbook sections 1 and 3**

Append to `docs/demo-setup.md` under the matching headings:

```markdown
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

## 3. Create the cluster (`infra/01-cluster`)

    cd infra/01-cluster
    cp terraform.tfvars.example terraform.tfvars   # optional, defaults are fine
    terraform init -backend-config=backend.hcl
    terraform apply

Takes about 5 minutes. The cluster is tagged `donotdelete`; some accounts run
nightly cleanup jobs that honour this tag.
```

- [ ] **Step 8: Commit**

```bash
git add infra/01-cluster docs/demo-setup.md
git commit -s -m "Add 01-cluster Terraform stack for the DOKS demo cluster"
```

---

### Task 3: Terraform stack `infra/02-bootstrap`

**Files:**
- Create: `infra/02-bootstrap/versions.tf`
- Create: `infra/02-bootstrap/backend.tf`
- Create: `infra/02-bootstrap/backend.hcl.example`
- Create: `infra/02-bootstrap/variables.tf`
- Create: `infra/02-bootstrap/providers.tf`
- Create: `infra/02-bootstrap/namespaces.tf`
- Create: `infra/02-bootstrap/argocd.tf`
- Create: `infra/02-bootstrap/argocd-values.yaml`
- Create: `infra/02-bootstrap/secrets.tf`
- Create: `infra/02-bootstrap/root-app.tf`
- Create: `infra/02-bootstrap/terraform.tfvars.example`
- Modify: `docs/demo-setup.md` (sections 2 and 4)

**Interfaces:**
- Consumes: cluster name from Task 2.
- Produces: namespaces `argocd`, `arc-runners`, `monitoring`; secrets `arc-runners/dac-github-app` (keys `github_app_id`, `github_app_installation_id`, `github_app_private_key`), `monitoring/alertmanager-slack` (key `webhook-url`), `argocd/repo-talk`; Argo CD release `argocd`; root Application `root` syncing `gitops/root`. Task 4 uses these exact names. Task 7 reproduces the same objects on kind from `argocd-values.yaml`.

- [ ] **Step 1: `versions.tf`, `backend.tf`, `backend.hcl.example`**

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
```

`backend.tf`:

```hcl
terraform {
  backend "s3" {
    # bucket and endpoints come from backend.hcl (gitignored):
    #   terraform init -backend-config=backend.hcl
    key    = "02-bootstrap/terraform.tfstate"
    region = "us-east-1"

    # DigitalOcean Spaces is S3-compatible but is not AWS.
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = false
  }
}
```

`backend.hcl.example`:

```hcl
# Copy to backend.hcl and edit. backend.hcl is gitignored.
# Use the same bucket as 01-cluster; the state key differs.
bucket = "my-dac-demo-tfstate"
endpoints = {
  s3 = "https://ams3.digitaloceanspaces.com"
}
```

- [ ] **Step 2: `variables.tf`**

```hcl
variable "cluster_name" {
  description = "Name of the DOKS cluster created by 01-cluster."
  type        = string
  default     = "dac-demo"
}

variable "repo_url" {
  description = "HTTPS URL of this repository (your fork). Also used in gitops/root/*.yaml."
  type        = string
  default     = "https://github.com/slashben/kubecon26us-detection-as-a-service-talk.git"
}

variable "repo_revision" {
  description = "Branch the root Application tracks."
  type        = string
  default     = "main"
}

variable "repo_private" {
  description = "Create an Argo CD repository credential using the GitHub App. Set false once the repo is public."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  type    = string
  default = "10.10.5"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.6"
}

variable "github_app_id" {
  description = "GitHub App ID (or client ID) used by ARC and, while private, by Argo CD."
  type        = string
  sensitive   = true
}

variable "github_app_installation_id" {
  description = "Installation ID of the GitHub App on the repository."
  type        = string
  sensitive   = true
}

variable "github_app_private_key" {
  description = "PEM private key of the GitHub App."
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for Alertmanager. Empty keeps the route with a placeholder URL."
  type        = string
  sensitive   = true
  default     = ""
}
```

- [ ] **Step 3: `providers.tf`**

```hcl
provider "digitalocean" {}

data "digitalocean_kubernetes_cluster" "demo" {
  name = var.cluster_name
}

locals {
  kubeconfig = data.digitalocean_kubernetes_cluster.demo.kube_config[0]
}

provider "kubernetes" {
  host                   = local.kubeconfig.host
  token                  = local.kubeconfig.token
  cluster_ca_certificate = base64decode(local.kubeconfig.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = local.kubeconfig.host
    token                  = local.kubeconfig.token
    cluster_ca_certificate = base64decode(local.kubeconfig.cluster_ca_certificate)
  }
}
```

- [ ] **Step 4: `namespaces.tf`**

```hcl
resource "kubernetes_namespace_v1" "argocd" {
  metadata { name = "argocd" }
}

resource "kubernetes_namespace_v1" "arc_runners" {
  metadata { name = "arc-runners" }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata { name = "monitoring" }
}
```

- [ ] **Step 5: `argocd.tf` and `argocd-values.yaml`**

`argocd-values.yaml` (shared with the kind script in Task 7, keep it provider-free):

```yaml
# Argo CD values for the demo. No ingress: reach the UI with
#   kubectl -n argocd port-forward svc/argocd-server 8080:80
configs:
  params:
    server.insecure: true
  cm:
    # Argo CD does not report Application health by default. Enabling it makes the
    # root app's sync waves wait for wave-0 children before creating wave-1 children.
    resource.customizations.health.argoproj.io_Application: |
      hs = {}
      hs.status = "Progressing"
      hs.message = ""
      if obj.status ~= nil then
        if obj.status.health ~= nil then
          hs.status = obj.status.health.status
          if obj.status.health.message ~= nil then
            hs.message = obj.status.health.message
          end
        end
      end
      return hs
  repositories:
    # ARC charts are OCI. Declaring the registry here lets Applications reference it
    # as a Helm repo without credentials.
    arc-charts:
      name: arc-charts
      type: helm
      url: ghcr.io/actions/actions-runner-controller-charts
      enableOCI: "true"
dex:
  enabled: false
notifications:
  enabled: false
```

`argocd.tf`:

```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  wait       = true
  timeout    = 600

  values = [file("${path.module}/argocd-values.yaml")]
}
```

- [ ] **Step 6: `secrets.tf`**

```hcl
resource "kubernetes_secret_v1" "arc_github_app" {
  metadata {
    name      = "dac-github-app"
    namespace = kubernetes_namespace_v1.arc_runners.metadata[0].name
  }
  data = {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }
}

resource "kubernetes_secret_v1" "alertmanager_slack" {
  metadata {
    name      = "alertmanager-slack"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    # Placeholder keeps the Slack route valid when no webhook is configured;
    # Alertmanager then only logs failed deliveries.
    "webhook-url" = var.slack_webhook_url != "" ? var.slack_webhook_url : "https://hooks.slack.com/services/placeholder/not/configured"
  }
}

resource "kubernetes_secret_v1" "argocd_repo" {
  count = var.repo_private ? 1 : 0

  metadata {
    name      = "repo-talk"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    type                    = "git"
    url                     = var.repo_url
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    githubAppPrivateKey     = var.github_app_private_key
  }
}
```

- [ ] **Step 7: `root-app.tf` and `terraform.tfvars.example`**

The root Application is created with the `argocd-apps` chart rather than `kubernetes_manifest`, because `kubernetes_manifest` needs the Application CRD to exist at plan time and on a fresh cluster it does not.

`root-app.tf`:

```hcl
resource "helm_release" "root_app" {
  name       = "root"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.repo_revision
          path           = "gitops/root"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, kubernetes_secret_v1.argocd_repo]
}
```

`terraform.tfvars.example`:

```hcl
cluster_name = "dac-demo"
repo_url     = "https://github.com/<you>/kubecon26us-detection-as-a-service-talk.git"
repo_private = true

github_app_id              = "123456"
github_app_installation_id = "12345678"
github_app_private_key     = <<EOF
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----
EOF

# Optional
slack_webhook_url = ""
```

- [ ] **Step 8: Validate, including the empty-webhook branch**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk/infra/02-bootstrap
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```
Expected: valid.

Then confirm the placeholder logic without a cluster:
```bash
terraform console <<'EOF'
"" != "" ? "x" : "https://hooks.slack.com/services/placeholder/not/configured"
EOF
```
Expected: the placeholder URL string. (A real `plan` needs the cluster and is done on the DO apply day.)

- [ ] **Step 9: Fill runbook sections 2 and 4**

```markdown
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
```

- [ ] **Step 10: Commit**

```bash
git add infra/02-bootstrap docs/demo-setup.md
git commit -s -m "Add 02-bootstrap Terraform stack: Argo CD, secrets, root Application"
```

---

### Task 4: GitOps tree: child Applications and values

**Files:**
- Create: `gitops/root/kubescape.yaml`
- Create: `gitops/root/monitoring.yaml`
- Create: `gitops/root/arc-controller.yaml`
- Create: `gitops/root/arc-runners.yaml`
- Create: `gitops/root/monitoring-config.yaml`
- Create: `gitops/root/rules.yaml`
- Create: `gitops/values/kubescape.yaml`
- Create: `gitops/values/monitoring.yaml`
- Create: `gitops/values/arc-controller.yaml`
- Create: `gitops/values/arc-runners.yaml`
- Create: `gitops/README.md`

**Interfaces:**
- Consumes: secret names and namespaces from Task 3; repo URL `https://github.com/slashben/kubecon26us-detection-as-a-service-talk.git`.
- Produces: Applications named `kubescape`, `monitoring`, `arc-controller`, `arc-runners`, `monitoring-config`, `rules`. Helm release names `kubescape`, `monitoring`, `arc-controller`, `dac-runners`. Task 5 fills the directories `gitops/monitoring/` and `gitops/rules/` that `monitoring-config` and `rules` point at. Task 8 checks these Application names.

- [ ] **Step 1: Wave-0 Applications**

`gitops/root/kubescape.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubescape
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://kubescape.github.io/helm-charts/
      chart: kubescape-operator
      targetRevision: 1.40.5
      helm:
        releaseName: kubescape
        valueFiles:
          - $values/gitops/values/kubescape.yaml
    - repoURL: https://github.com/slashben/kubecon26us-detection-as-a-service-talk.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: kubescape
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 5m
```

`gitops/root/monitoring.yaml`: same shape with `name: monitoring`, chart source `repoURL: https://prometheus-community.github.io/helm-charts`, `chart: kube-prometheus-stack`, `targetRevision: 92.8.0`, `releaseName: monitoring`, `valueFiles: [$values/gitops/values/monitoring.yaml]`, destination namespace `monitoring`, and `syncOptions` of `CreateNamespace=true` **and** `ServerSideApply=true` (the CRDs exceed the client-side annotation limit).

`gitops/root/arc-controller.yaml`: same shape with `name: arc-controller`, chart source `repoURL: ghcr.io/actions/actions-runner-controller-charts`, `chart: gha-runner-scale-set-controller`, `targetRevision: 0.15.0`, `releaseName: arc-controller`, `valueFiles: [$values/gitops/values/arc-controller.yaml]`, destination namespace `arc-systems`.

- [ ] **Step 2: Wave-1 Applications**

`gitops/root/arc-runners.yaml`: same shape, `sync-wave: "1"`, `name: arc-runners`, chart `gha-runner-scale-set` at `0.15.0` from the same OCI registry, `releaseName: dac-runners`, `valueFiles: [$values/gitops/values/arc-runners.yaml]`, destination namespace `arc-runners`.

`gitops/root/monitoring-config.yaml` (directory source, single source):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/slashben/kubecon26us-detection-as-a-service-talk.git
    targetRevision: main
    path: gitops/monitoring
    directory:
      recurse: false
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 5
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 5m
```

`gitops/root/rules.yaml`: identical with `name: rules`, `path: gitops/rules`, destination namespace `kubescape`.

- [ ] **Step 3: Kubescape and ARC values**

`gitops/values/kubescape.yaml`:

```yaml
clusterName: dac-demo

capabilities:
  runtimeObservability: enable
  runtimeDetection: enable

nodeAgent:
  config:
    # host:port, no scheme (node-agent pkg/exporters/alert_manager.go).
    # alertmanager-operated is the headless service the Prometheus operator always creates.
    alertManagerExporterUrls:
      - alertmanager-operated.monitoring.svc.cluster.local:9093
    stdoutExporter: true
    # Chart default is 1h after the first alert, which hides a second demo run.
    ruleCooldown:
      ruleCooldownDuration: 30s
      ruleCooldownAfterCount: 1
```

`gitops/values/arc-controller.yaml`:

```yaml
# Chart defaults. File exists so the Application's valueFiles entry resolves.
replicaCount: 1
```

`gitops/values/arc-runners.yaml`:

```yaml
githubConfigUrl: https://github.com/slashben/kubecon26us-detection-as-a-service-talk
# Pre-created by infra/02-bootstrap (or hack/kind-up.sh); never in Git.
githubConfigSecret: dac-github-app

runnerScaleSetName: dac-runners
minRunners: 0
maxRunners: 3

# Argo CD renders with `helm template`, which cannot `lookup` the controller's
# service account, so name it explicitly: <controller release>-gha-rs-controller.
controllerServiceAccount:
  namespace: arc-systems
  name: arc-controller-gha-rs-controller

# No containerMode: the job runs inside the runner container. No Docker daemon,
# no Kubernetes hook. Trivy's fs scan needs neither.
template:
  metadata:
    labels:
      app.kubernetes.io/name: dac-runner
      dac.kubescape.io/role: ci-runner
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:2.338.0
        command: ["/home/runner/run.sh"]
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            memory: 2Gi
```

- [ ] **Step 4: Monitoring values**

`gitops/values/monitoring.yaml`:

```yaml
grafana:
  enabled: false

alertmanager:
  enabled: true
  alertmanagerSpec:
    retention: 24h
    # Pick up AlertmanagerConfig objects labelled dac=alerts (gitops/monitoring/).
    alertmanagerConfigSelector:
      matchLabels:
        dac: alerts
    # By default the operator adds a namespace="<config namespace>" matcher to every
    # AlertmanagerConfig route. Kubescape alerts carry namespace=arc-runners, so that
    # default would never match. None disables the injected matcher.
    alertmanagerConfigMatcherStrategy:
      type: None
    resources:
      requests:
        cpu: 50m
        memory: 128Mi

prometheus:
  prometheusSpec:
    retention: 24h
    resources:
      requests:
        cpu: 200m
        memory: 768Mi
      limits:
        memory: 2Gi

# Not needed for the demo; saves a node's worth of scraping.
kubeEtcd:
  enabled: false
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
```

- [ ] **Step 5: `gitops/README.md`**

```markdown
# GitOps tree

Synced by the Argo CD root Application that `infra/02-bootstrap` creates.

| Path | What |
|---|---|
| `root/` | One Application per component. Wave 0: kubescape, monitoring, arc-controller. Wave 1: arc-runners, monitoring-config, rules. |
| `values/` | Helm values for the chart-based Applications. |
| `monitoring/` | AlertmanagerConfig routing Kubescape alerts to Slack. |
| `rules/` | Kubescape `Rules` objects: the detection-as-code part of the demo. |

Chart versions are pinned in `root/*.yaml`. The repo URL appears in `root/*.yaml` and
`values/arc-runners.yaml`; forks change it there (see `docs/demo-setup.md`).
```

- [ ] **Step 6: Render every chart with its values**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
rtk proxy helm template kubescape kubescape/kubescape-operator --version 1.40.5 -n kubescape -f gitops/values/kubescape.yaml > /dev/null && echo kubescape ok
rtk proxy helm template monitoring prometheus-community/kube-prometheus-stack --version 92.8.0 -n monitoring -f gitops/values/monitoring.yaml > /dev/null && echo monitoring ok
rtk proxy helm template arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --version 0.15.0 -n arc-systems -f gitops/values/arc-controller.yaml > /dev/null && echo arc-controller ok
rtk proxy helm template dac-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --version 0.15.0 -n arc-runners -f gitops/values/arc-runners.yaml > /dev/null && echo arc-runners ok
```
Expected: four `ok` lines. Then confirm the rendered node-agent config carries the Alertmanager URL and the runner pod carries the labels:
```bash
rtk proxy helm template kubescape kubescape/kubescape-operator --version 1.40.5 -n kubescape -f gitops/values/kubescape.yaml | rtk proxy grep -c "alertmanager-operated.monitoring.svc.cluster.local:9093"
rtk proxy helm template dac-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --version 0.15.0 -n arc-runners -f gitops/values/arc-runners.yaml | rtk proxy grep -c "dac.kubescape.io/role: ci-runner"
```
Expected: each count at least 1.

- [ ] **Step 7: Commit**

```bash
git add gitops/root gitops/values gitops/README.md
git commit -s -m "Add Argo CD child Applications and Helm values for the demo cluster"
```

---

### Task 5: Alertmanager routing and the placeholder Rules object

**Files:**
- Create: `gitops/monitoring/alertmanagerconfig-kubescape.yaml`
- Create: `gitops/rules/README.md`
- Create: `gitops/rules/dac-rules.yaml`

**Interfaces:**
- Consumes: secret `monitoring/alertmanager-slack` key `webhook-url` (Task 3); label `dac: alerts` selected by Task 4's monitoring values.
- Produces: `AlertmanagerConfig/dac-kubescape` in `monitoring`; `Rules/dac-rules` in `kubescape`. Task 8 checks both exist on kind.

- [ ] **Step 1: AlertmanagerConfig**

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: dac-kubescape
  namespace: monitoring
  labels:
    dac: alerts
spec:
  route:
    receiver: default
    groupBy: ["alertname", "rule_id", "pod_name"]
    groupWait: 5s
    groupInterval: 30s
    repeatInterval: 1h
    routes:
      # Labels set by node-agent's Alertmanager exporter. Pod labels are not
      # forwarded, so the route keys on the runner namespace.
      - receiver: slack
        matchers:
          - name: alertname
            value: KubescapeRuleViolated
          - name: namespace
            value: arc-runners
  receivers:
    - name: default
    - name: slack
      slackConfigs:
        - apiURL:
            name: alertmanager-slack
            key: webhook-url
          sendResolved: false
          title: '{{ .CommonLabels.rule_name }} in {{ .CommonLabels.namespace }}/{{ .CommonLabels.pod_name }}'
          text: |-
            {{ range .Alerts }}{{ .Annotations.summary }}
            rule: {{ .Labels.rule_id }}  severity: {{ .Labels.severity }}  node: {{ .Labels.node_name }}
            process: {{ .Labels.comm }} (pid {{ .Labels.pid }}, parent {{ .Labels.pcomm }})
            {{ end }}
```

- [ ] **Step 2: Placeholder Rules object and README**

`gitops/rules/dac-rules.yaml`:

```yaml
# Detection rules for the demo. Edited on stage: add a rule, open a PR, merge,
# Argo CD syncs it, node-agent picks it up without a restart.
apiVersion: kubescape.io/v1
kind: Rules
metadata:
  name: dac-rules
  namespace: kubescape
spec:
  rules:
    - name: "Placeholder (disabled)"
      enabled: false
      id: "DAC-0000"
      description: "Keeps this object non-empty until the demo rules are added."
      expressions:
        message: "'placeholder'"
        uniqueId: "'placeholder'"
        ruleExpression:
          - eventType: "exec"
            expression: "false"
      profileDependency: 2
      severity: 1
      supportPolicy: false
      isTriggerAlert: false
      tags:
        - "placeholder"
```

`gitops/rules/README.md`:

```markdown
# Rules

Kubescape `Rules` objects (`rules.kubescape.io/v1`) synced into the `kubescape`
namespace by the `rules` Application. Each entry follows the schema in
[kubescape/rulelibrary](https://github.com/kubescape/rulelibrary) (`rules-crd.yaml` there
is the full upstream set). `profileDependency` 2 means the rule needs no application
profile, which matters for ephemeral runner pods.

`dac-rules.yaml` holds the demo's rules. It starts with one disabled placeholder.
```

- [ ] **Step 3: Check the Rules object against the CRD schema offline**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
go run github.com/yannh/kubeconform/cmd/kubeconform@v0.7.0 \
  -schema-location default \
  -schema-location /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/helm-charts/charts/kubescape-operator/crds/rules.crd.yaml \
  -summary gitops/rules/dac-rules.yaml
```
If kubeconform cannot take a CRD file directly, convert it:
```bash
python3 -I -c '
import yaml,json,sys
crd=yaml.safe_load(open(sys.argv[1]))
print(json.dumps(crd["spec"]["versions"][0]["schema"]["openAPIV3Schema"]))' \
  /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/helm-charts/charts/kubescape-operator/crds/rules.crd.yaml \
  > /tmp/claude-1000/-home-ben-projects-workspace-detection-as-a-service-kubecon-talk/02077009-29d5-40d3-af7d-2a8af3110547/scratchpad/rules-v1.json
go run github.com/yannh/kubeconform/cmd/kubeconform@v0.7.0 -schema-location /tmp/claude-1000/-home-ben-projects-workspace-detection-as-a-service-kubecon-talk/02077009-29d5-40d3-af7d-2a8af3110547/scratchpad/rules-v1.json -summary gitops/rules/dac-rules.yaml
```
Expected: `Summary: 1 resource found ... Valid: 1`. The AlertmanagerConfig is checked on kind in Task 8 (its CRD comes with the chart).

- [ ] **Step 4: Commit**

```bash
git add gitops/monitoring gitops/rules
git commit -s -m "Add Alertmanager Slack route and placeholder Rules object"
```

---

### Task 6: Workflows and the stub compromised action

**Files:**
- Create: `.github/workflows/scan.yaml`
- Create: `.github/workflows/scan-compromised.yaml`
- Create: `.github/actions/trivy-compromised/action.yaml`
- Create: `.github/actions/trivy-compromised/README.md`

**Interfaces:**
- Consumes: runner label `dac-runners` (Task 4).
- Produces: two `workflow_dispatch` workflows; the stub action prints `DAC-SIMULATION placeholder` and exits 0. The attack work later replaces the stub body only.

- [ ] **Step 1: Clean scan workflow**

`.github/workflows/scan.yaml`:

```yaml
name: Trivy scan (clean)

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  scan:
    runs-on: dac-runners
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Trivy filesystem scan
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          scan-type: fs
          scan-ref: .
          severity: HIGH,CRITICAL
          exit-code: "0"
```

- [ ] **Step 2: Simulated compromised workflow and stub action**

`.github/workflows/scan-compromised.yaml`:

```yaml
name: Trivy scan (simulated compromise)

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  scan:
    runs-on: dac-runners
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Simulated compromised Trivy action
        uses: ./.github/actions/trivy-compromised
```

`.github/actions/trivy-compromised/action.yaml`:

```yaml
name: trivy-compromised (simulation)
description: >-
  Harmless stand-in for the compromised Trivy action from the TeamPCP advisory.
  Simulated behaviours are added by the attack-simulation work; this version only
  prints a marker.
runs:
  using: composite
  steps:
    - name: Marker
      shell: bash
      run: echo "DAC-SIMULATION placeholder: no simulated behaviour yet"
```

`.github/actions/trivy-compromised/README.md`:

```markdown
# trivy-compromised (simulation)

A local composite action that stands in for the compromised `trivy-action` release
described in the TeamPCP advisory. It never runs the real thing. The behaviours it
simulates (harmlessly) are chosen from the advisory's IoC analysis and documented here
when they are added. Until then it prints a marker line and exits 0.
```

- [ ] **Step 3: Lint**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 -color
```
Expected: no output (no findings). actionlint warns on unknown `runs-on` labels only for GitHub-hosted names; `dac-runners` is accepted.

- [ ] **Step 4: Commit**

```bash
git add .github
git commit -s -m "Add clean and simulated-compromise Trivy workflows on dac-runners"
```

---

### Task 7: Local validation scripts on kind

**Files:**
- Create: `hack/kind-up.sh`
- Create: `hack/kind-down.sh`
- Create: `hack/README.md`
- Modify: `docs/demo-setup.md` (section "Local validation with kind")

**Interfaces:**
- Consumes: `infra/02-bootstrap/argocd-values.yaml` (Task 3), secret names from Task 3, root app shape from Task 3.
- Produces: a kind cluster `dac-kind` with Argo CD and the root app, from env vars `REPO_URL`, `REPO_REVISION`, `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_FILE`, `SLACK_WEBHOOK_URL`. Task 8 runs it.

- [ ] **Step 1: `hack/kind-up.sh`**

```bash
#!/usr/bin/env bash
# Bring up a local kind cluster that mirrors infra/02-bootstrap: Argo CD, the three
# secrets, the root Application. Used to validate the gitops/ tree before any cloud spend.
#
# Env (all optional except where noted):
#   REPO_URL                     default: this repo's origin URL (https form)
#   REPO_REVISION                default: current branch
#   REPO_PRIVATE                 default: true; "false" skips the Argo CD repo credential
#   GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PRIVATE_KEY_FILE
#                                default: placeholders; arc-runners stays degraded without real ones
#   SLACK_WEBHOOK_URL            default: placeholder
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
cluster="${KIND_CLUSTER_NAME:-dac-kind}"
argocd_chart_version="${ARGOCD_CHART_VERSION:-10.10.5}"
argocd_apps_chart_version="${ARGOCD_APPS_CHART_VERSION:-2.0.6}"

origin="$(git -C "$repo_root" remote get-url origin)"
origin_https="$(sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##' <<<"$origin").git"
REPO_URL="${REPO_URL:-$origin_https}"
REPO_REVISION="${REPO_REVISION:-$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)}"
REPO_PRIVATE="${REPO_PRIVATE:-true}"
GITHUB_APP_ID="${GITHUB_APP_ID:-0}"
GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-0}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/placeholder/not/configured}"

if [[ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]]; then
  key_file="$GITHUB_APP_PRIVATE_KEY_FILE"
else
  key_file="$(mktemp)"
  echo "placeholder" >"$key_file"
fi

if ! kind get clusters | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --wait 120s
fi
kubectl config use-context "kind-$cluster" >/dev/null

for ns in argocd arc-runners monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl -n arc-runners create secret generic dac-github-app \
  --from-literal=github_app_id="$GITHUB_APP_ID" \
  --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
  --from-file=github_app_private_key="$key_file" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url="$SLACK_WEBHOOK_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ "$REPO_PRIVATE" == "true" ]]; then
  kubectl -n argocd create secret generic repo-talk \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=githubAppID="$GITHUB_APP_ID" \
    --from-literal=githubAppInstallationID="$GITHUB_APP_INSTALLATION_ID" \
    --from-file=githubAppPrivateKey="$key_file" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
fi

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --version "$argocd_chart_version" -n argocd \
  -f "$repo_root/infra/02-bootstrap/argocd-values.yaml" \
  --wait --timeout 10m

helm upgrade --install root argo/argocd-apps \
  --version "$argocd_apps_chart_version" -n argocd \
  --set-json "applications={\"root\":{\"namespace\":\"argocd\",\"project\":\"default\",\"source\":{\"repoURL\":\"$REPO_URL\",\"targetRevision\":\"$REPO_REVISION\",\"path\":\"gitops/root\"},\"destination\":{\"server\":\"https://kubernetes.default.svc\",\"namespace\":\"argocd\"},\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":true},\"syncOptions\":[\"CreateNamespace=true\"]}}}"

echo
echo "Argo CD is up. Watch the apps with:"
echo "  kubectl -n argocd get applications -w"
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "    password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

- [ ] **Step 2: `hack/kind-down.sh` and `hack/README.md`**

`hack/kind-down.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
kind delete cluster --name "${KIND_CLUSTER_NAME:-dac-kind}"
```

`hack/README.md`:

```markdown
# hack

Local validation of the GitOps tree on kind, without DigitalOcean.

    ./hack/kind-up.sh      # kind cluster + Argo CD + root Application
    ./hack/kind-down.sh

`kind-up.sh` mirrors what `infra/02-bootstrap` does on DOKS, using the same Argo CD
values file. Without real GitHub App credentials the `arc-runners` Application stays
degraded; everything else should reach Synced/Healthy.
```

- [ ] **Step 3: Make scripts executable and lint**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
chmod +x hack/kind-up.sh hack/kind-down.sh
bash -n hack/kind-up.sh hack/kind-down.sh && echo syntax ok
```
Expected: `syntax ok`. If `shellcheck` is installed, run `shellcheck hack/*.sh` and expect no findings.

- [ ] **Step 4: Fill the runbook section**

```markdown
## Local validation with kind

    ./hack/kind-up.sh
    kubectl -n argocd get applications -w

Expect `kubescape`, `monitoring`, `arc-controller`, `monitoring-config` and `rules` to
reach `Synced / Healthy` within about 5 minutes. `arc-runners` needs real GitHub App
credentials; pass them as `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID` and
`GITHUB_APP_PRIVATE_KEY_FILE`. The repo must be reachable by Argo CD: while it is
private, the same GitHub App needs the Contents permission.
```

- [ ] **Step 5: Commit**

```bash
git add hack docs/demo-setup.md
git commit -s -m "Add kind scripts that mirror the Argo CD bootstrap for local validation"
```

---

### Task 8: End-to-end validation on kind

**Files:**
- Modify: `docs/demo-setup.md` (sections 5 and Troubleshooting)
- Modify: `README.md` ("What's in this repo" table)

**Interfaces:**
- Consumes: everything above. The branch under test must be pushed, because Argo CD pulls from GitHub, not from the working tree.

- [ ] **Step 1: Push the branch and bring up kind**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
git push -u origin HEAD
./hack/kind-up.sh
```
Expected: script ends with the "Argo CD is up" message. Requires the GitHub App credentials in the environment for the private repo; without them, set `REPO_PRIVATE=false` only if the repo has been made public.

- [ ] **Step 2: Wait for the wave-0 apps**

Run:
```bash
for app in kubescape monitoring arc-controller; do
  kubectl -n argocd wait application/$app --for=jsonpath='{.status.health.status}'=Healthy --timeout=900s
done
kubectl -n argocd get applications
```
Expected: the three apps show `Synced` and `Healthy`. If `monitoring` is stuck `OutOfSync` with a "metadata.annotations: Too long" error, `ServerSideApply=true` is missing from `gitops/root/monitoring.yaml`.

- [ ] **Step 3: Wait for the wave-1 apps**

Run:
```bash
for app in monitoring-config rules; do
  kubectl -n argocd wait application/$app --for=jsonpath='{.status.sync.status}'=Synced --timeout=600s
done
kubectl -n monitoring get alertmanagerconfig dac-kubescape
kubectl -n kubescape get rules dac-rules
kubectl -n argocd get application arc-runners -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```
Expected: both objects exist. `arc-runners` is `Synced` and either `Healthy` (real credentials) or `Degraded`/`Progressing` (placeholders) with the listener pod logging an authentication error; nothing else is affected.

- [ ] **Step 4: Check node-agent and the exporter wiring**

Run:
```bash
kubectl -n kubescape get pods -l app.kubernetes.io/name=node-agent
kubectl -n kubescape get configmap node-agent -o jsonpath='{.data.config\.json}' | rtk proxy grep -o '"alertManagerExporterUrls":[^]]*]'
kubectl -n kubescape logs ds/node-agent --tail=50 | rtk proxy grep -i -E "alertmanager|rule" | head
```
Expected: node-agent pods Running (kind runs on the host kernel, so eBPF works on this machine), the configmap shows the Alertmanager URL, and the logs show the rule manager loading rules without errors.

- [ ] **Step 5: Check Alertmanager received the config**

Run:
```bash
kubectl -n monitoring exec alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- \
  amtool config show --alertmanager.url=http://localhost:9093 | rtk proxy grep -A3 "KubescapeRuleViolated"
```
Expected: a route block with the two matchers and a receiver whose name ends in `slack`. If the pod name differs, find it with `kubectl -n monitoring get pods -l app.kubernetes.io/name=alertmanager`.

- [ ] **Step 6: Route test (Review Focus 5)**

Run:
```bash
kubectl -n monitoring exec alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- \
  amtool config routes test --alertmanager.url=http://localhost:9093 \
  alertname=KubescapeRuleViolated namespace=arc-runners
kubectl -n monitoring exec alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- \
  amtool config routes test --alertmanager.url=http://localhost:9093 \
  alertname=KubescapeRuleViolated namespace=default
```
Expected: the first prints the slack receiver (`monitoring/dac-kubescape/slack`), the second prints the default receiver.

- [ ] **Step 7: Send a synthetic alert end to end**

Run:
```bash
kubectl -n monitoring exec alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager -- \
  amtool alert add --alertmanager.url=http://localhost:9093 \
  alertname=KubescapeRuleViolated namespace=arc-runners rule_id=DAC-TEST pod_name=synthetic \
  --annotation=summary="synthetic test alert"
sleep 15
kubectl -n monitoring logs alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager --tail=20 | rtk proxy grep -i slack
```
Expected: with a placeholder webhook, a log line reporting a failed Slack notification (proves the route fired, Review Focus 2). With a real webhook, the message lands in Slack.

- [ ] **Step 8: Tear down**

Run: `./hack/kind-down.sh`
Expected: cluster deleted.

- [ ] **Step 9: Fill runbook section 5 and Troubleshooting, update README**

`docs/demo-setup.md`:

```markdown
## 5. Verify

    kubectl -n argocd get applications          # all Synced/Healthy
    kubectl -n kubescape get pods               # node-agent Running on every node
    kubectl -n arc-runners get pods             # listener pod Running; runners appear per job
    kubectl -n monitoring port-forward svc/alertmanager-operated 9093   # Alertmanager UI

Trigger a job from the GitHub UI: Actions → "Trivy scan (clean)" → Run workflow. A
runner pod appears in `arc-runners`, runs the job and disappears.

## Troubleshooting

- **`arc-runners` Degraded, listener logs 401/404.** Wrong installation ID, the app is
  not installed on this fork, or missing the Actions/Administration permissions.
- **Argo CD cannot fetch the repo (private fork).** The GitHub App needs Contents:
  Read, and `repo_private = true` must be set so the credential is created.
- **`monitoring` OutOfSync with "annotations too long".** `ServerSideApply=true` is
  missing on `gitops/root/monitoring.yaml`.
- **node-agent CrashLoopBackOff on DOKS.** The node kernel lacks a required eBPF
  feature. Check `kubectl -n kubescape logs ds/node-agent`; this is a blocker to
  raise before building further, not something to work around in values.
- **Slack messages never arrive.** The webhook variable was empty at apply time;
  Alertmanager logs show the placeholder URL failing. Set `slack_webhook_url` and
  re-apply `02-bootstrap`.
```

`README.md` table rows to add under "What's in this repo":

```markdown
| [`infra/`](infra/) | Terraform: `01-cluster` (DOKS) and `02-bootstrap` (Argo CD, secrets, root app) |
| [`gitops/`](gitops/) | Argo CD Applications, Helm values, Alertmanager routing, Kubescape `Rules` |
| [`.github/`](.github/) | Trivy workflows on the in-cluster runners and the harmless simulated-compromise action |
| [`hack/`](hack/) | kind scripts for local validation |
| [`docs/demo-setup.md`](docs/demo-setup.md) | How to bring up the demo cluster |
```

Also replace the README's "More to come" line with a sentence saying setup is documented in `docs/demo-setup.md` and the rules and attack simulation are still to come.

- [ ] **Step 10: Commit**

```bash
git add docs/demo-setup.md README.md
git commit -s -m "Document demo cluster setup, verification and troubleshooting"
```

---

### Task 9: DigitalOcean apply (only when the user says go)

**Files:** none new. Uses `infra/01-cluster` and `infra/02-bootstrap`.

**Interfaces:**
- Consumes: Spaces bucket and keys, GitHub App credentials, `backend.hcl` and `terraform.tfvars` in both stacks (gitignored).

- [ ] **Step 1: Confirm the user has asked for the DO apply in this session.** If not, stop here; the plan is complete without this task.

- [ ] **Step 2: Create the cluster**

```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk/infra/01-cluster
terraform init -backend-config=backend.hcl -input=false
terraform plan -out=tfplan
terraform apply tfplan
doctl kubernetes cluster get dac-demo --format Name,Status,Tags
```
Expected: status `running`, tags include `donotdelete`.

- [ ] **Step 3: Bootstrap**

```bash
cd ../02-bootstrap
terraform init -backend-config=backend.hcl -input=false
terraform plan -out=tfplan
terraform apply tfplan
doctl kubernetes cluster kubeconfig save dac-demo
kubectl -n argocd get applications -w
```
Expected: the same end state as Task 8 steps 2 and 3, now with `arc-runners` Healthy.

- [ ] **Step 4: eBPF check on DOKS (handover risk 2)**

```bash
kubectl -n kubescape get pods -l app.kubernetes.io/name=node-agent -o wide
kubectl -n kubescape logs ds/node-agent --tail=100 | rtk proxy grep -i -E "error|fatal" | head
```
Expected: one Running node-agent per node and no fatal eBPF loading errors. Report the result either way; if it fails, stop and escalate rather than tuning values.

- [ ] **Step 5: Run the clean workflow**

```bash
gh workflow run scan.yaml
sleep 20
kubectl -n arc-runners get pods -w
gh run list --workflow=scan.yaml --limit 1
```
Expected: a `dac-runners-*` pod appears, the run completes successfully, the pod disappears.

- [ ] **Step 6: Record the outcome in `backstage/`** (workspace, not the talk repo): cluster version, node kernel version (`kubectl get nodes -o wide`), time to provision, time to all-Synced, anything surprising.
