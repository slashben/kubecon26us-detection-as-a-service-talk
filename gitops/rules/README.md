# Rules

Kubescape `Rules` objects (`apiVersion: kubescape.io/v1`, CRD `rules.kubescape.io`) synced into the `kubescape`
namespace by the `rules` Application. Each entry follows the schema in
[kubescape/rulelibrary](https://github.com/kubescape/rulelibrary) (`rules-crd.yaml` there
is the full upstream set). `profileDependency` 2 means the rule needs no application
profile, which matters for ephemeral runner pods.

`dac-rules.yaml` holds the demo's rules. It starts with one disabled placeholder.

`upstream-rules.yaml` is the upstream rule library (`kubescape-rules`), vendored verbatim
with its source commit in the header. Enabled/disabled flags are upstream's.

`binding-dac-runners.yaml` is the `RuntimeRuleAlertBinding` that makes node-agent evaluate
rules at all: it selects pods labelled `dac.kubescape.io/role=ci-runner` in `arc-runners`
and binds every rule tagged `dac` (demo rules) or `context:kubernetes` (all upstream rules).
Tag each demo rule with `dac`.
