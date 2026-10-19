# Attack Emulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the demo a simulated compromised CI run that performs harmless stand-ins for the TeamPCP indicators of compromise, plus four Kubescape runtime rules that detect them and raise alerts.

**Architecture:** The emulated malicious action is a composite GitHub Action whose steps run inside the existing runner pod, which node-agent already watches. Four profile-free `Rules` entries match the IoCs on literal event fields. No image, no second scale set; the clean-vs-compromised contrast is the two workflows.

**Tech Stack:** Kubescape `Rules` CRD (CEL), GitHub Actions composite action, Argo CD GitOps, kubeconform, actionlint.

**Spec:** [docs/superpowers/specs/2026-10-19-attack-emulation-design.md](../specs/2026-10-19-attack-emulation-design.md)

## Global Constraints

- No TCP/HTTP/exfil connection is ever made to any C2 host, IP, or tunnel. IoCs appear only as DNS queries and as process-argument strings.
- All writes go to the ephemeral pod's own filesystem (`$HOME`, `/tmp`); nothing persists.
- Every demo rule sets `profileDependency: 2`, `enabled: true`, `isTriggerAlert: true`, and carries the tag `dac` (the existing `RuntimeRuleAlertBinding` selects it).
- CEL follows rulelibrary conventions (`rulelibrary/AGENTS.md`, `docs/writing-optimized-cel.md`): collapse `==` OR-chains to `x in [...]`.
- Repo will be published: no secrets, no internal URLs. kubectl against the live cluster always passes `--context do-nyc3-dac-demo`; prefix helm/kubectl reads with `rtk proxy` to avoid output truncation.
- The clean workflow (`scan.yaml`) stays unchanged and must remain silent for the four `dac` rules.

## Review Focus

- **Short-lived pod races event processing:** the runner pod exits seconds after the job; node-agent may miss late events. The emulation ends with a `sleep` so the container lives long enough; Task 3 confirms alerts actually arrive.
- **`event.comm` of a shebang/interpreted script** may be `python3`, not `sysmon.py`; the `exec` rule must still fire. Covered by the exec rule matching argv as well as comm (Task 1), verified live (Task 3).
- **DNS name trailing dot:** the sensor may report `example.com.`; a rule matching only `example.com` would miss. Covered by including both forms in the DNS rule's list (Task 1).
- **Incidental IoC tokens trip the exec rule:** commands like `chmod`/`cp`/`nslookup` carrying a path or domain could raise false alerts and break the silent clean run. Covered by shaping the emulation so only the intended `python3 .../sysmon.py` invocation carries the tokens (Task 2), verified by the clean-run baseline (Task 3).
- **Upstream rules add noise:** the 25 upstream rules are also bound to these pods and may fire on a Trivy run. Verification filters alerts to the four `dac` rule names rather than asserting an empty alert list (Task 3).

---

### Task 1: Author the four detection rules

**Files:**
- Modify: `gitops/rules/dac-rules.yaml` (replace the single placeholder entry)
- Modify: `gitops/rules/README.md` (describe the four rules instead of a placeholder)
- Test: offline kubeconform against the Rules CRD schema

**Interfaces:**
- Consumes: the `Rules` CRD schema at `helm-charts/charts/kubescape-operator/crds/rules.crd.yaml` (required entry fields: `enabled, id, name, description, expressions, profileDependency, severity, supportPolicy, isTriggerAlert, mitreTechnique, mitreTactic`; `profileDependency` enum is 0/1/2).
- Produces: rule ids `DAC-0001` (dns), `DAC-0002` (open, persistence), `DAC-0003` (open, exfil), `DAC-0004` (exec, backdoor process), each tagged `dac`. Task 2's emulation must produce the events these match; Task 3 triggers them.

- [ ] **Step 1: Write the rules (this is the implementation; the test is kubeconform in Step 2)**

Replace the entire contents of `gitops/rules/dac-rules.yaml` with:

```yaml
# Detection rules for the demo. Edited on stage: add a rule, open a PR, merge,
# Argo CD syncs it, node-agent picks it up without a restart.
#
# All four match TeamPCP IoCs on literal event fields, with profileDependency: 2
# so they fire on the first run without a learned baseline (runner pods are
# ephemeral and never complete a profile). Tagged "dac" so the existing
# RuntimeRuleAlertBinding evaluates them on the CI runner pods.
apiVersion: kubescape.io/v1
kind: Rules
metadata:
  name: dac-rules
  namespace: kubescape
spec:
  rules:
    - name: "TeamPCP C2 beacon (DNS)"
      enabled: true
      id: "DAC-0001"
      description: "A DNS query for one of the TeamPCP C2 or payload domains."
      expressions:
        message: "'C2 beacon: DNS query for ' + event.name + ' from ' + event.containerName"
        uniqueId: "event.name"
        ruleExpression:
          - eventType: "dns"
            expression: >
              event.name in ['scan.aquasecurtiy.org', 'scan.aquasecurtiy.org.',
              'hackmoltrepeat.com', 'hackmoltrepeat.com.',
              'tdtqy-oyaaa-aaaae-af2dq-cai.raw.icp0.io', 'tdtqy-oyaaa-aaaae-af2dq-cai.raw.icp0.io.',
              'plug-tab-protective-relay.trycloudflare.com', 'plug-tab-protective-relay.trycloudflare.com.']
      profileDependency: 2
      severity: 10
      supportPolicy: false
      isTriggerAlert: true
      mitreTactic: "TA0011"
      mitreTechnique: "T1071.004"
      tags:
        - "dac"
        - "c2"
        - "dns"
    - name: "TeamPCP persistence backdoor accessed"
      enabled: true
      id: "DAC-0002"
      description: "A write to the systemd user backdoor path ~/.config/systemd/user/sysmon.py."
      expressions:
        message: "'Persistence backdoor file accessed: ' + event.path + ' by ' + event.comm"
        uniqueId: "event.path"
        ruleExpression:
          - eventType: "open"
            expression: "event.path.endsWith('/systemd/user/sysmon.py')"
      profileDependency: 2
      severity: 8
      supportPolicy: false
      isTriggerAlert: true
      mitreTactic: "TA0003"
      mitreTechnique: "T1543.002"
      tags:
        - "dac"
        - "persistence"
    - name: "TeamPCP exfiltration archive created"
      enabled: true
      id: "DAC-0003"
      description: "Creation of the tpcp.tar.gz exfiltration archive."
      expressions:
        message: "'Exfiltration archive touched: ' + event.path + ' by ' + event.comm"
        uniqueId: "event.path"
        ruleExpression:
          - eventType: "open"
            expression: "event.path.endsWith('/tpcp.tar.gz')"
      profileDependency: 2
      severity: 8
      supportPolicy: false
      isTriggerAlert: true
      mitreTactic: "TA0009"
      mitreTechnique: "T1560.001"
      tags:
        - "dac"
        - "exfiltration"
    - name: "TeamPCP backdoor process executed"
      enabled: true
      id: "DAC-0004"
      description: "Execution of the sysmon.py backdoor, carrying the C2 IP as an argument."
      expressions:
        message: "'Backdoor process executed: ' + event.comm + ' (pid ' + string(event.pid) + ')'"
        uniqueId: "event.comm + '_' + string(event.pid)"
        ruleExpression:
          - eventType: "exec"
            expression: "event.comm == 'sysmon.py' || event.args.exists(a, string(a) == '45.148.10.212' || string(a).endsWith('sysmon.py'))"
      profileDependency: 2
      severity: 10
      supportPolicy: false
      isTriggerAlert: true
      mitreTactic: "TA0002"
      mitreTechnique: "T1059.006"
      tags:
        - "dac"
        - "backdoor"
        - "exec"
```

- [ ] **Step 2: Validate against the CRD schema (the test)**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
go run github.com/yannh/kubeconform/cmd/kubeconform@v0.7.0 \
  -schema-location default \
  -schema-location /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/helm-charts/charts/kubescape-operator/crds/rules.crd.yaml \
  -summary gitops/rules/dac-rules.yaml
```
Expected: `Summary: 1 resource found ... Valid: 1`.

If kubeconform will not read the CRD file directly, convert it first and point `-schema-location` at the JSON:
```bash
python3 -I -c '
import yaml,json,sys
crd=yaml.safe_load(open(sys.argv[1]))
print(json.dumps(crd["spec"]["versions"][0]["schema"]["openAPIV3Schema"]))' \
  /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/helm-charts/charts/kubescape-operator/crds/rules.crd.yaml \
  > /tmp/claude-1000/-home-ben-projects-workspace-detection-as-a-service-kubecon-talk/02077009-29d5-40d3-af7d-2a8af3110547/scratchpad/rules-v1.json
go run github.com/yannh/kubeconform/cmd/kubeconform@v0.7.0 \
  -schema-location /tmp/claude-1000/-home-ben-projects-workspace-detection-as-a-service-kubecon-talk/02077009-29d5-40d3-af7d-2a8af3110547/scratchpad/rules-v1.json \
  -summary gitops/rules/dac-rules.yaml
```
Expected: `Summary: 1 resource found ... Valid: 1`. The CRD schema does not validate CEL syntax; that is checked live in Task 3.

- [ ] **Step 3: Update the rules README**

In `gitops/rules/README.md`, replace the line:
```
`dac-rules.yaml` holds the demo's rules. It starts with one disabled placeholder.
```
with:
```
`dac-rules.yaml` holds the demo's four detection rules (ids DAC-0001..DAC-0004):
a C2 DNS beacon, a systemd-user persistence backdoor file access, an exfiltration
archive, and the backdoor process execution. All use profileDependency 2 (no
application profile needed) and are tagged `dac`, so the binding evaluates them
on the CI runner pods. They match the TeamPCP IoCs emulated by
`.github/actions/trivy-compromised`.
```

- [ ] **Step 4: Commit**

```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
git add gitops/rules/dac-rules.yaml gitops/rules/README.md
git commit -s -m "Add four TeamPCP detection rules to dac-rules"
```

---

### Task 2: Fill the compromised composite action with the IoC emulation

**Files:**
- Modify: `.github/actions/trivy-compromised/action.yaml` (replace the marker stub)
- Test: offline actionlint over the workflows and action

**Interfaces:**
- Consumes: the rule ids from Task 1 — the emulation must produce a DNS query for each C2 domain (DAC-0001), a write to `~/.config/systemd/user/sysmon.py` (DAC-0002), a `tpcp.tar.gz` under `/tmp` (DAC-0003), and a `python3 .../sysmon.py` exec carrying `45.148.10.212` (DAC-0004).
- Produces: the composite action `./.github/actions/trivy-compromised`, already referenced by `.github/workflows/scan-compromised.yaml`. No workflow change needed.

- [ ] **Step 1: Write the composite action (implementation; actionlint in Step 2 is the test)**

Replace the entire contents of `.github/actions/trivy-compromised/action.yaml` with:

```yaml
name: trivy-compromised (simulation)
description: >-
  Harmless stand-in for the compromised Trivy action from the TeamPCP advisory.
  Runs a real Trivy scan, then emulates the advisory's indicators of compromise
  (DNS beacon, persistence backdoor, exfil archive, backdoor process) so the
  Kubescape demo rules fire. No real C2 contact: the C2 hosts and IP appear only
  as DNS queries and process arguments, and every write lands in the ephemeral
  runner pod, which is destroyed seconds later.
runs:
  using: composite
  steps:
    - name: Trivy filesystem scan
      uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
      with:
        scan-type: fs
        scan-ref: .
        severity: HIGH,CRITICAL
        exit-code: "0"

    - name: DAC-SIMULATION emulate TeamPCP IoCs
      shell: bash
      run: |
        set -u
        echo "DAC-SIMULATION: emulating TeamPCP IoCs (harmless; no C2 contact)"

        # In-cluster DNS resolver (CoreDNS). DNS queries go here only; the C2
        # domains are never resolved against the public internet.
        RESOLVER="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)"
        echo "DAC-SIMULATION: using resolver ${RESOLVER}"

        # 1) C2 beacon (DAC-0001): a DNS query per C2/payload domain. The query
        #    emits the dns event even when it does not resolve. No connection.
        for d in scan.aquasecurtiy.org hackmoltrepeat.com \
                 tdtqy-oyaaa-aaaae-af2dq-cai.raw.icp0.io \
                 plug-tab-protective-relay.trycloudflare.com; do
          echo "DAC-SIMULATION: DNS lookup ${d}"
          nslookup "${d}" "${RESOLVER}" || true
        done

        # 2) Persistence backdoor (DAC-0002): write the sysmon.py path. A shell
        #    redirect, so no process argv carries the path at this point.
        mkdir -p "${HOME}/.config/systemd/user"
        cat > "${HOME}/.config/systemd/user/sysmon.py" <<'PY'
        #!/usr/bin/env python3
        # DAC-SIMULATION backdoor stand-in; prints a marker and exits.
        import sys
        print("DAC-SIMULATION sysmon", sys.argv[1:])
        PY

        # 3) Exfil archive (DAC-0003): tar a dummy file into tpcp.tar.gz.
        echo "DAC-SIMULATION collected data" > /tmp/dac-collected.txt
        tar czf /tmp/tpcp.tar.gz -C /tmp dac-collected.txt

        # 4) Backdoor process (DAC-0004): run sysmon.py via python3 with the C2
        #    IP and domain as arguments. This is the only process whose argv
        #    carries the IoC tokens, so no incidental command trips the rule.
        python3 "${HOME}/.config/systemd/user/sysmon.py" \
          --c2 45.148.10.212 --host scan.aquasecurtiy.org || true

        # Keep the container alive briefly so node-agent processes the events
        # before the ephemeral runner pod is torn down.
        sleep 10
        echo "DAC-SIMULATION: done"
```

- [ ] **Step 2: Lint the action and workflows (the test)**

Run:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 -color
```
Expected: no output (no findings). `dac-runners` is accepted via `.github/actionlint.yaml`. If actionlint reports a shellcheck finding on the `run` script, fix the script (not the rule) and re-run until clean.

- [ ] **Step 3: Commit**

```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
git add .github/actions/trivy-compromised/action.yaml
git commit -s -m "Emulate TeamPCP IoCs in the compromised Trivy action"
```

---

### Task 3: Live end-to-end validation on the dac-demo cluster

**Files:**
- Modify: `docs/talk-plan.md` (document the clean-vs-compromised demo and the four rules)
- Modify: `docs/superpowers/specs/2026-10-19-attack-emulation-design.md` (resolve the `event.comm` open question with the observed value)
- Test: run both workflows on the live cluster and confirm the alerts

This task is the real RED→GREEN: before the merge, a compromised run produces no `dac` alerts (the rules did not exist / were the placeholder); after it, all four fire. The rules and action must be on `main` and synced by Argo CD before running.

- [ ] **Step 1: Merge to main and let Argo CD sync**

Live validation needs the rules and action on `main`, because Argo CD follows `main`. Merge the working branch and push:
```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git checkout main && git pull
git merge --no-ff "$BRANCH"
git push
```
This merge is the integration point for this plan; the final finishing-a-development-branch step then only cleans up the branch. Then confirm the rules landed:
```bash
rtk proxy kubectl --context do-nyc3-dac-demo -n kubescape get rules dac-rules -o jsonpath='{.spec.rules[*].id}'; echo
```
Expected: `DAC-0001 DAC-0002 DAC-0003 DAC-0004`.

- [ ] **Step 2: Confirm node-agent loaded the rules without CEL errors**

Run:
```bash
rtk proxy kubectl --context do-nyc3-dac-demo -n kubescape logs ds/node-agent --tail=200 | rtk proxy grep -i -E "DAC-000|compile|cel|error" | tail -40
```
Expected: node-agent reports the dac rules among its loaded rules and logs no CEL compile error for `DAC-0001..DAC-0004`. If a rule fails to compile, fix the CEL in `dac-rules.yaml` (Task 1), re-validate with kubeconform, commit, and re-sync before continuing.

- [ ] **Step 3: Baseline — run the clean workflow, expect no dac alerts**

Trigger the clean scan and wait for it to finish:
```bash
gh workflow run scan.yaml --ref main
```
Wait ~2 minutes, then check Alertmanager for any alert whose `rule_id` starts with `DAC-`:
```bash
rtk proxy kubectl --context do-nyc3-dac-demo -n monitoring port-forward svc/alertmanager-operated 9093 >/tmp/pf-am.log 2>&1 &
PF=$!; sleep 3
curl -s http://localhost:9093/api/v2/alerts | rtk proxy grep -o '"rule_id":"DAC-[0-9]*"' | sort -u
kill $PF
```
Expected: no `DAC-` rule_id in the output. The clean run is silent for the demo rules.

- [ ] **Step 4: Fire — run the compromised workflow, expect all four dac alerts**

Trigger the compromised scan:
```bash
gh workflow run scan-compromised.yaml --ref main
```
Wait ~2 minutes (the job runs Trivy, emulates the IoCs, then sleeps 10s), then read the alerts:
```bash
rtk proxy kubectl --context do-nyc3-dac-demo -n monitoring port-forward svc/alertmanager-operated 9093 >/tmp/pf-am.log 2>&1 &
PF=$!; sleep 3
curl -s http://localhost:9093/api/v2/alerts | rtk proxy grep -o '"rule_id":"DAC-[0-9]*"' | sort -u
kill $PF
```
Expected: all four — `DAC-0001`, `DAC-0002`, `DAC-0003`, `DAC-0004`. If one is missing, inspect node-agent for the matching event:
```bash
rtk proxy kubectl --context do-nyc3-dac-demo -n kubescape logs ds/node-agent --tail=300 | rtk proxy grep -i -E "sysmon|tpcp|aquasecurtiy|DAC-000"
```
Diagnose against the Review Focus rows (short-lived pod, `event.comm`, trailing dot, incidental tokens), fix the owning file, re-validate, re-sync, and re-run this step.

- [ ] **Step 5: Record the observed `event.comm` and update docs**

From the Step 4 node-agent output, note whether the backdoor exec's `event.comm` was `sysmon.py` or `python3`. In `docs/superpowers/specs/2026-10-19-attack-emulation-design.md`, replace the Open questions entry about `event.comm` with the observed value, e.g.:
```
## Resolved

- `event.comm` for the `python3 .../sysmon.py` invocation was observed as
  `<observed value>` on the live sensor; DAC-0004 matches it via <comm|argv>.
```
In `docs/talk-plan.md`, add or update the demo section to describe: the clean workflow (`scan.yaml`) runs Trivy and stays silent; the compromised workflow (`scan-compromised.yaml`) runs the same scan plus the emulated action, firing DAC-0001..DAC-0004 in Alertmanager; and the on-stage beat of editing a rule via PR and letting Argo CD sync it.

- [ ] **Step 6: Commit the documentation updates**

```bash
cd /home/ben/projects/workspace-detection-as-a-service-kubecon-talk/kubecon26us-detection-as-a-service-talk
git add docs/talk-plan.md docs/superpowers/specs/2026-10-19-attack-emulation-design.md
git commit -s -m "Document attack-emulation demo and record observed event.comm"
```

---

## Notes for the executor

- The `dac-demo` cluster is live (kubectl context `do-nyc3-dac-demo`); credentials are sourced from `backstage/dac-demo.env` in the workspace before any `doctl`/cluster command. See the memory `demo-cluster-live`.
- `gh` acts on the repo `slashben/kubecon26us-detection-as-a-service-talk`; `gh workflow run` needs the workflow on the default branch.
- Do not run the emulation outside a runner pod labelled `dac.kubescape.io/role: ci-runner` in `arc-runners`; the binding only evaluates rules there. For faster iteration than full workflow runs, you may exec the emulation script in a throwaway pod carrying that label in `arc-runners`, then watch node-agent — but the committed test of record is the workflow run in Step 4.
