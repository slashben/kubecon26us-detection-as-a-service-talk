# hack

Local validation of the GitOps tree on kind, without DigitalOcean.

    ./hack/kind-up.sh      # kind cluster + Argo CD + root Application
    ./hack/kind-down.sh

`kind-up.sh` mirrors what `infra/02-bootstrap` does on DOKS, using the same Argo CD
values file. Without real GitHub App credentials the `arc-runners` Application stays
degraded; everything else should reach Synced/Healthy.
