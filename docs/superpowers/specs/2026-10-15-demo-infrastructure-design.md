# Demo infrastructure design

Date: 2026-10-15. Status: approved design, not yet built.

## Goal

Provide the cluster, GitOps plumbing, runtime detection and CI runners that the talk's
live demo runs on. The demo loop is notify → author → test → PR → deploy → alert. This
design covers the infrastructure that makes the deploy and alert steps real. It does not
cover the attack simulation content or the detection rules; those plug into the stubs
this design leaves behind.

Success means:

- One attendee with a DigitalOcean account, a GitHub fork and a GitHub App can bring the
  whole demo cluster up by following `docs/demo-setup.md`.
- A workflow with `runs-on: dac-runners` executes on an ephemeral runner pod inside the
  cluster, and Kubescape watches that pod.
- A Kubescape alert reaches Alertmanager, shows in the Alertmanager UI, and is routed to
  Slack when a webhook is configured.
- Changing a file under `gitops/rules/` and merging is enough to change what the cluster
  detects, with no Terraform run.
- The GitOps tree is validated on a local kind cluster before any DigitalOcean spend.

## Decisions carried over from the handover

| Topic | Decision |
|---|---|
| Cloud | DigitalOcean Kubernetes (DOKS) |
| IaC | Two Terraform stacks: `01-cluster`, `02-bootstrap` |
| GitOps | Argo CD app-of-apps, Applications and values in this repo |
| Runners | Actions Runner Controller, scale set `dac-runners`, GitHub App auth, no Docker-in-Docker |
| Example workload | Trivy GitHub Action, filesystem scan |
| Compromise | Never the real one. A local stub action, filled in later |

Decisions made for this design:

| Topic | Decision |
|---|---|
| Terraform state | DigitalOcean Spaces via the `s3` backend. One bucket, one key per stack |
| Alert sink | Alertmanager UI always. Slack route via an optional webhook variable |
| GitHub App | Created by the operator in the GitHub UI. One app serves both ARC and the Argo CD repo credential |
| Node pool | 3 nodes, `s-4vcpu-8gb` |
| Local validation | `hack/kind-up.sh` reproduces the bootstrap on kind with the same GitOps tree |

## Repository layout

```
infra/
  01-cluster/            VPC, DOKS cluster, node pool
  02-bootstrap/          Argo CD, namespaces, secrets, root Application
gitops/
  root/                  child Application manifests (what the root app syncs)
  values/                Helm values, one file per child app
  monitoring/            AlertmanagerConfig for the Slack route
  rules/                 Kubescape Rules objects (one placeholder to start)
hack/
  kind-up.sh             local validation path
  kind-down.sh
.github/
  workflows/scan.yaml                 clean Trivy run
  workflows/scan-compromised.yaml     runs the stub action
  actions/trivy-compromised/          stub composite action
docs/
  demo-setup.md          attendee runbook
```

## Terraform

### State backend

Both stacks declare the `s3` backend with the flags Spaces needs:
`skip_credentials_validation`, `skip_requesting_account_id`, `skip_metadata_api_check`,
`skip_region_validation`, `skip_s3_checksum`, `region = "us-east-1"`, and the Spaces
endpoint for the chosen region. Keys are `01-cluster/terraform.tfstate` and
`02-bootstrap/terraform.tfstate`. Bucket name is passed with `-backend-config` so the
committed files hold no account-specific value.

Credentials come from `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` set to a Spaces
key pair. The bucket is a documented one-time step in `docs/demo-setup.md`, not a third
Terraform stack.

### 01-cluster

Resources: `digitalocean_vpc`, `digitalocean_kubernetes_cluster` with one default node
pool. The cluster carries the tag `donotdelete`: the DigitalOcean account used for the
demo runs a nightly job that deletes every Kubernetes cluster without that tag, and the
tag is also harmless on any other account. Version comes from `data "digitalocean_kubernetes_versions"` filtered to a
configurable minor prefix, so the pin lives in one variable. Variables: `cluster_name`
(default `dac-demo`), `region` (default `nyc3`), `node_size` (default `s-4vcpu-8gb`),
`node_count` (default 3), `kubernetes_version_prefix`. Outputs: cluster name and id.
Nothing else, so the stack can be destroyed and recreated without touching Git.

### 02-bootstrap

Looks up the cluster with `data "digitalocean_kubernetes_cluster"` by name and configures
the `kubernetes` and `helm` providers from its kubeconfig. Then:

1. Namespaces `argocd`, `arc-runners`, `monitoring`. The other namespaces are created
   by Argo CD `CreateNamespace=true` on the child apps.
2. Argo CD from the `argo/argo-cd` chart, pinned version, with values that enable the
   Application health check so sync waves across child apps wait for each other, and
   keep the server insecure behind port-forward (no ingress, no public endpoint).
3. Secrets from sensitive variables, never from Git:
   - `arc-runners/dac-github-app`: `github_app_id`, `github_app_installation_id`,
     `github_app_private_key`.
   - `argocd/repo-talk`: Argo CD repository credential for the talk repo using the same
     GitHub App. Created only while `repo_private = true`.
   - `monitoring/alertmanager-slack`: `webhook-url`. When `slack_webhook_url` is empty
     the value is a placeholder URL, so the route exists and only delivery fails.
4. The root `Application` in `argocd`, source `gitops/root/` of this repo at `main`
   (branch is a variable), automated sync with prune and self-heal.

Variables: `cluster_name`, `repo_url`, `repo_revision`, `repo_private`, `github_app_id`,
`github_app_installation_id`, `github_app_private_key`, `slack_webhook_url`,
`argocd_chart_version`. Values come from a gitignored `terraform.tfvars`.

## GitOps tree

### Child Applications

All children are multi-source Applications: the upstream chart as one source, this repo
as a second source providing `gitops/values/<app>.yaml` through `$values`. Automated
sync with prune and self-heal, retry with backoff. Sync waves by annotation:

| Wave | App | Chart | Namespace |
|---|---|---|---|
| 0 | kubescape | `kubescape/kubescape-operator` | `kubescape` |
| 0 | monitoring | `prometheus-community/kube-prometheus-stack` | `monitoring` |
| 0 | arc-controller | `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller` | `arc-systems` |
| 1 | arc-runners | `oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set` | `arc-runners` |
| 1 | monitoring-config | directory `gitops/monitoring/` | `monitoring` |
| 1 | rules | directory `gitops/rules/` | `kubescape` |

Chart versions are pinned in the Application manifests. Wave 1 apps depend on CRDs
installed by wave 0 apps, and retry covers the window where a CRD is not yet served.

### Values

- Kubescape: `capabilities.runtimeDetection: enable`,
  `nodeAgent.config.alertManagerExporterUrls` set to the Alertmanager service in
  `monitoring`, `nodeAgent.config.ruleCooldown` shortened so a demo can re-fire within
  minutes, `nodeAgent.config.stdoutExporter: true` kept for `kubectl logs` on stage.
  Learning period stays at the chart default; the rule set decides later whether
  profiles matter for ephemeral runner pods (handover risk 1).
- Monitoring: Grafana disabled, Alertmanager enabled with
  `alertmanagerConfigSelector` matching label `dac: alerts`, retention short. Resource
  requests trimmed for a 3-node demo cluster.
- ARC controller: chart defaults.
- ARC runners: `githubConfigUrl` is the talk repo URL, `githubConfigSecret` is
  `dac-github-app`, `runnerScaleSetName: dac-runners`, `minRunners: 0`,
  `maxRunners: 3`, no `containerMode` (the job runs inside the runner container, no
  Docker daemon, no Kubernetes hook). Pod template labels
  `app.kubernetes.io/name: dac-runner` and `dac.kubescape.io/role: ci-runner` give the
  workload a stable identity for rules and alert routes.

### Monitoring config

One `AlertmanagerConfig` labelled `dac: alerts` in `monitoring`. Route: alerts with
`alertname = KubescapeRuleViolated` and `namespace = arc-runners` go to receiver
`slack`, everything else to the default. The receiver reads the webhook URL from secret
`alertmanager-slack`. Label names come from the node-agent Alertmanager exporter
(`pkg/exporters/alert_manager.go`): it sets `alertname`, `rule_name`, `rule_id`,
`namespace`, `pod_name`, `container_name`, `workload_uid`, `node_name` and `severity`.
It does not forward pod labels, so the route keys on the namespace, which is why the
runner scale set has a namespace of its own.

### Rules

`gitops/rules/` starts with a single `Rules` object (`rules.kubescape.io/v1`) holding
one disabled placeholder entry, so the Application has something to sync and the file
the talk edits on stage already exists.

## Workflows and the stub action

- `scan.yaml`: `workflow_dispatch` only, `runs-on: dac-runners`, checkout and
  `aquasecurity/trivy-action` pinned by commit SHA, `scan-type: fs`, `scan-ref: .`.
- `scan-compromised.yaml`: same trigger and runner, calls
  `./.github/actions/trivy-compromised`.
- `.github/actions/trivy-compromised/action.yaml`: composite action that prints a
  marker line and exits 0. Its README says the simulated behaviours come from the
  advisory analysis and are added later.

## Local validation on kind

`hack/kind-up.sh` creates a kind cluster, installs Argo CD with the same chart version
and values as the bootstrap stack, creates the same three secrets from environment
variables, and applies the same root Application. `hack/kind-down.sh` deletes the
cluster. This path proves the GitOps tree syncs and Kubescape, Prometheus and the ARC
controller become healthy. The runner scale set only becomes healthy with real GitHub
App credentials, so that check is run once the credentials exist.

## Error handling and operational notes

- A missing or wrong GitHub App credential leaves `arc-runners` degraded and nothing
  else. Argo CD shows the listener pod's error; the runbook names the three common
  causes (wrong installation id, app not installed on the repo, missing permission).
- An empty Slack webhook degrades only Slack delivery.
- Node-agent needs eBPF support on the DOKS node kernel. First DO apply includes
  checking node-agent pods reach Ready; if not, that is handover risk 2 and gets
  escalated before building further.
- Cluster provisioning takes around 5 minutes and the GitOps sync another 5 to 10. The
  runbook says to bring the cluster up well before the talk.

## Testing

- `terraform fmt -check` and `terraform validate` on both stacks (validate runs with a
  local backend override so it needs no Spaces credentials).
- Plain manifests under `gitops/`, validated with `kubectl apply --dry-run=client` on
  the kind cluster once the CRDs exist there.
- `helm template` of each child app with its values file, to catch value typos before
  Argo CD does.
- The kind run above, ending with every child app Synced and Healthy except
  `arc-runners` when no credentials are present.
- `actionlint` on the workflows.

## Out of scope

- Which detection rules are deployed, and the content of the simulated compromise.
- Alertmanager routing beyond one Slack route.
- A public Argo CD or Alertmanager endpoint. Both are reached through port-forward.
- Recorded fallback and rehearsal notes (workspace `backstage/`).
