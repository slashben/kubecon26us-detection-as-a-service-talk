# Rules

Kubescape `Rules` objects (`apiVersion: kubescape.io/v1`, CRD `rules.kubescape.io`) synced into the `kubescape`
namespace by the `rules` Application. Each entry follows the schema in
[kubescape/rulelibrary](https://github.com/kubescape/rulelibrary) (`rules-crd.yaml` there
is the full upstream set). `profileDependency` 2 means the rule needs no application
profile, which matters for ephemeral runner pods.

`dac-rules.yaml` holds the demo's four detection rules (ids DAC-0001..DAC-0004):
a C2 DNS beacon, a systemd-user persistence backdoor file access, an exfiltration
archive, and the backdoor process execution. All use profileDependency 2 (no
application profile needed) and are tagged `dac`, so the binding evaluates them
on the CI runner pods. They match the TeamPCP IoCs emulated by
`.github/actions/trivy-compromised`.

DAC-0001 matches both answered DNS responses (`dns`) and unanswered queries
(`dnsQuery`), so a C2/typosquat lookup that returns NXDOMAIN still fires. The
`dnsQuery` path needs `dnsRuleForwarding` enabled (see
`gitops/values/kubescape.yaml`) and node-agent >= v0.3.278; on older agents the
expression loads but never matches, and the `dns` path still covers domains that
resolve.

`upstream-rules.yaml` is the upstream rule library (`kubescape-rules`), vendored verbatim
with its source commit in the header. Enabled/disabled flags are upstream's.

`binding-dac-runners.yaml` is the `RuntimeRuleAlertBinding` that makes node-agent evaluate
rules at all: it selects pods labelled `dac.kubescape.io/role=ci-runner` in `arc-runners`
and binds every rule tagged `dac` (demo rules) or `context:kubernetes` (all upstream rules).
Tag each demo rule with `dac`.
