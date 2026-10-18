# GitOps tree

Synced by the Argo CD root Application that `infra/02-bootstrap` creates.

| Path | What |
|---|---|
| `root/` | One Application per component. Wave 0: kubescape, monitoring, arc-controller. Wave 1: arc-runners, monitoring-config, rules. |
| `values/` | Helm values for the chart-based Applications. |
| `monitoring/` | AlertmanagerConfig routing Kubescape alerts to Slack. |
| `rules/` | Kubescape `Rules` objects: the detection-as-code part of the demo. |

Chart versions are pinned in `root/*.yaml`. The repo URL appears in `root/*.yaml` and
`values/arc-runners.yaml`; forks change it there (see `docs/demo-setup.md`). The child
Applications track `main`; only the root Application's revision is configurable.
