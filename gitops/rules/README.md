# Rules

Kubescape `Rules` objects (`apiVersion: kubescape.io/v1`, CRD `rules.kubescape.io`) synced into the `kubescape`
namespace by the `rules` Application. Each entry follows the schema in
[kubescape/rulelibrary](https://github.com/kubescape/rulelibrary) (`rules-crd.yaml` there
is the full upstream set). `profileDependency` 2 means the rule needs no application
profile, which matters for ephemeral runner pods.

The demo's detection rules are **not here yet**: that is the point of the demo. They are
authored from the TeamPCP indicators of compromise, land in this directory through a
PR, and Argo CD deploys them. See "Writing rules" in the repo's `CLAUDE.md` for the
schema, the sensor's event model and the validation step
(`./hack/validate-rules.sh`). The rules as authored for the talk, for reference and for
diffing, are in `docs/reference-rules/`.

`upstream-rules.yaml` is the upstream rule library (`kubescape-rules`), vendored verbatim
with its source commit in the header. Enabled/disabled flags are upstream's.

`binding-dac-runners.yaml` is the `RuntimeRuleAlertBinding` that makes node-agent evaluate
rules at all: it selects pods labelled `dac.kubescape.io/role=ci-runner` in `arc-runners`
and binds every rule tagged `dac` (demo rules) or `context:kubernetes` (all upstream rules).
Tag each demo rule with `dac`.
