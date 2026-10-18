# Rules

Kubescape `Rules` objects (`apiVersion: kubescape.io/v1`, CRD `rules.kubescape.io`) synced into the `kubescape`
namespace by the `rules` Application. Each entry follows the schema in
[kubescape/rulelibrary](https://github.com/kubescape/rulelibrary) (`rules-crd.yaml` there
is the full upstream set). `profileDependency` 2 means the rule needs no application
profile, which matters for ephemeral runner pods.

`dac-rules.yaml` holds the demo's rules. It starts with one disabled placeholder.
