# Talk plan: Detection as Code (KubeCon NA 2026)

## Summary

Shift-left is solved (scanners, admission control, SBOM + VEX), but when a high-severity
CVE drops with "patch coming soon", production goes quiet for days. Kubescape makes
runtime detection a Kubernetes resource: a Rule CRD (CEL expression evaluated next to
the eBPF tracers) that you review in a PR, version in Git, deploy with Argo/Flux, and
roll back like any manifest. Running example: the **TeamPCP Trivy compromise**. Goal on
stage: "CVE published" → "rule deployed" in under an hour, with a visible clock.

## Structure (timeline, ~30 min)

One continuous demo of the loop: **notify → author → test → PR → deploy → alert**.

| Section | Min | Who | Content |
|---|---|---|---|
| The uncomfortable corner | 3 | Constanze | Shift-left done; CVE drops; start the clock. You know your apps, your clusters, and that you're vulnerable. |
| Why detection as a resource | 3 | Ben | Everything else went declarative; detection belongs in GitOps. Circle diagram. |
| 1. Notified | 3 | | TeamPCP Trivy advisory; SBOM + VEX answers "am I exposed, and where". Clock checkpoint 1. |
| 2. Author | 6 | Ben | What the eBPF sensor sees (exec/file/network/syscalls). IoCs → CEL rule in a Rule CRD. No-IoC path: node-agent autodiscovery on non-prod → SBOB profiles → mock attack → confusion matrix. |
| 3. PR | 4 | Constanze | PR with the Rule CRD (IoC repo) and signed profiles (app chart repo). Signatures = consciously accepting a detection's blind spots and cost. Rules/SBOB fragments shareable across tools. |
| 4. Deploy | 3 | | Merge, Argo/Flux reconciles, live with no app restart. Clock checkpoint 2. |
| 5. Alert | 4 | | Trigger the compromise, alert fires with context. Best case in real life: it never fires. |
| Stop the clock | 3 | both | Elapsed time; effort is in IoC→rule translation and profile calibration; where it goes wrong; Q&A. |

**Two scenarios:** (1) IoCs published → write a CEL rule; (2) no IoCs → rely on
anomaly detection against application profiles (SBOB).

**Decided (2026-11-02, both speakers):**
- Both demo segments are **recorded clips** on the slides, not live. Ben's clips should be
  visual (PR merge, Argo CD sync, alert arriving), not terminal-only.
- **Separate clusters.** The rule path (this repo) stays on its Argo CD cluster; the SBOB
  profile path runs on Constanze's two deliberately different clusters (Flux-managed) to
  show how kernel/k8s/CNI/metal-vs-VM shift profile-based detection. Her blind spots are
  stated, not hidden. Her files land in this repo once cleaned up (currently in
  `k8sstormcenter/bob` PR 246).

**Open decisions:**
- Consolidate on one node-agent version? Possible; only the NXDOMAIN typosquat beat needs
  >= v0.3.278. Constanze's call.
- Whether a php2shell detection joins the rule set (raised by Constanze, unanswered).
- Alertmanager → Slack is still a placeholder webhook; recording needs either a real webhook
  or the Alertmanager UI as the alert visual.

**Tech still in flight:** review/cleanup of the CEL rules; the signature feature
(demo-ready, not merge-ready).

## Implemented demo (verified on the dac-demo cluster)

The scenario-1 (IoCs → CEL rule) path is built and tested end to end.

- **Two workflows.** `scan.yaml` runs a clean Trivy filesystem scan. `scan-compromised.yaml`
  runs the same scan plus `.github/actions/trivy-compromised`, a composite action that
  harmlessly emulates the TeamPCP indicators of compromise (no real C2 contact; writes only
  to the ephemeral runner pod). Both run on the ARC `dac-runners` self-hosted runners.
- **Four rules** in `gitops/rules/dac-rules.yaml`, tagged `dac`, `profileDependency: 2`
  (fire on the first run, no learned baseline): DAC-0001 C2 DNS beacon, DAC-0002 systemd-user
  persistence backdoor (`sysmon.py`), DAC-0003 exfil archive (`tpcp.tar.gz`), DAC-0004 the
  backdoor process execution.
- **DNS exfil/C2 that never resolves.** DAC-0001 matches both answered responses (`dns`) and
  unanswered queries (`dnsQuery`), so the typosquat `scan.aquasecurtiy.org` (NXDOMAIN) fires
  just like the resolving ICP-canister C2. This needs node-agent DNS query forwarding
  (`dnsRuleForwarding`), first shipped in node-agent **v0.3.278**; the cluster pins that image
  since chart 1.40.5 still ships v0.3.219.
- **Verified:** the clean run raises no `dac` alerts; the compromised run fires all four rules
  (DAC-0001 on all four C2 domains) into Alertmanager, routed on `namespace=arc-runners`.
- **The clean run is not silent, and that is part of the story.** Upstream R1001 "Drifted
  process executed" fires on *both* runs: `trivy-action` downloads the Trivy binary at
  runtime, so a process not in the image executes. Narrate it rather than hide it: a CI
  action that pulls a binary at run time is exactly the surface TeamPCP exploited. Clean
  run = 1 alert (drift), compromised run = drift + the four `dac` rules.
