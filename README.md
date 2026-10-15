# Detection as Code: from CVE to deployed runtime rule in under an hour

Companion repository for the KubeCon + CloudNativeCon North America 2026 talk
**"Detection as Code"**.

> **Status:** work in progress. Demo code, manifests and slides will be added here as
> the talk takes shape.

## The problem

Platform teams have shift-left covered: scanners on every PR, admission control on every
deploy, SBOM + VEX on every image. Then a high-severity CVE drops with "patch coming
soon", and all of it goes quiet for days while a known-exploitable workload sits in
production. Most teams have no declarative answer for this corner of day-2 Kubernetes.

## The idea

[Kubescape](https://kubescape.io), the CNCF incubating project for Kubernetes security,
makes runtime detection a Kubernetes resource. A detection is a **Rule CRD** holding a
CEL expression that is evaluated against events from Kubescape's eBPF sensor. That
means a detection can be:

- reviewed in a pull request,
- versioned in Git,
- deployed with Argo CD or Flux,
- rolled back like any other manifest.

Using the TeamPCP Trivy compromise as the running example, the talk walks one loop live:

**notified → author → test → PR → deploy → alert**

It covers what the eBPF sensor sees, how to turn an advisory's IoCs into a Rule CRD, how
application profiles (SBOB) catch anomalies when no IoCs exist yet, and a CI/CD workflow
that gets from "CVE published" to "rule deployed" in under an hour.

## What's in this repo

| Path | Contents |
|---|---|
| [`docs/talk-plan.md`](docs/talk-plan.md) | Talk narrative, timeline and open decisions |

More to come: demo cluster setup, Rule CRDs, GitOps manifests and attack simulation
scripts.

## Related projects

- [kubescape/node-agent](https://github.com/kubescape/node-agent): eBPF sensor and CEL rule engine
- [kubescape/rulelibrary](https://github.com/kubescape/rulelibrary): Kubescape's library of runtime detection rules
- [kubescape/storage](https://github.com/kubescape/storage): storage for application profiles, SBOMs and VEX
- [kubescape/helm-charts](https://github.com/kubescape/helm-charts): Helm chart for installing Kubescape

## License

[Apache License 2.0](LICENSE)
