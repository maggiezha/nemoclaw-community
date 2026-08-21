<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# Hermes

Self-improving agent with a learning loop, from
[Nous Research](https://github.com/NousResearch/hermes-agent); upstream source at
[`NVIDIA/NemoClaw/agents/hermes`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/hermes).
Like OpenClaw, Hermes is a long-running gateway agent with a dashboard — the difference is
its own OpenAI-compatible API port (`8642`), its own health probe, and its own sandbox
policy file.

**Not yet independently validated end-to-end against a live cluster.** The build-arg
contract, entrypoint (`/usr/local/bin/nemoclaw-start`), and sandbox policy below were
verified against upstream NemoClaw source (Dockerfile, `manifest.yaml`,
`policy-additions.yaml`) but not run through a live OpenShell + Kubernetes install by this
recipe yet — please file an issue with anything you find while trying it, especially on
`dgx02`-class (8×H100) hardware.

Comparing agents? See [`../README.md`](../README.md) for the comparison table and
shared sandbox-policy notes.

## Prerequisites

Everything in the recipe root [Prerequisites](../../README.md#prerequisites) — this agent
adds nothing beyond the shared OpenShell-path requirements (Docker Buildx + a registry
every node can pull from, the OpenShell CLI, and Agent Sandbox CRDs).

## Quick start

Run from the recipe root (`examples/recipes/nvidia/kubernetes-gpu-autoscaling/`) after
completing [steps 1–3](../../README.md#quick-start) (clone, GPUs/DCGM, GPU inference + HPA
— identical for every agent).

### 1. Agent Sandbox CRDs + OpenShell gateway

Shared across all three agents — full OIDC / unauthenticated-eval details in
[OpenShell details](../../README.md#openshell-details).

```bash
source versions.env
kubectl apply -f \
  "https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${AGENT_SANDBOX_VERSION}/manifest.yaml"

export OPENSHELL_OIDC_ISSUER=https://idp.example.com/realms/openshell
export OPENSHELL_OIDC_AUDIENCE=openshell-cli
./scripts/install-openshell-k8s.sh
# Dedicated eval without OIDC: ALLOW_UNAUTHENTICATED_OPENSHELL=1 +
# OPENSHELL_UNAUTHENTICATED_ACK=dedicated-cluster-port-forward-only
```

### 2. Build and push the Hermes sandbox image

```bash
export HERMES_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-hermes-k8s:v0.0.104
./agents/hermes/build-sandbox-image.sh
```

### 3. Connect the OpenShell CLI

Terminal 1 — keep running:

```bash
kubectl -n nemoclaw-sandboxes port-forward service/openshell 8080:8080
```

Terminal 2 — client mTLS + gateway registration (same for every agent):

```bash
MTLS_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/openshell/gateways/nemoclaw-k8s/mtls"
mkdir -p "${MTLS_DIR}"
for key in ca.crt tls.crt tls.key; do
  kubectl get secret openshell-client-tls -n nemoclaw-sandboxes \
    -o "jsonpath={.data.${key//./\\.}}" | base64 -d >"${MTLS_DIR}/${key}"
done
chmod 600 "${MTLS_DIR}"/*
openshell gateway add https://127.0.0.1:8080 \
  --local --name nemoclaw-k8s \
  --oidc-issuer "${OPENSHELL_OIDC_ISSUER}" \
  --oidc-client-id "${OPENSHELL_OIDC_CLIENT_ID:-openshell-cli}" \
  --oidc-audience "${OPENSHELL_OIDC_AUDIENCE}"
# Unauth eval: omit --oidc-* flags
openshell status
```

### 4. Create, verify, and run the sandbox

```bash
export HERMES_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-hermes-k8s:v0.0.104
export INFERENCE_MODEL=llama3.2:3b   # must match the GPU chart model
./agents/hermes/create-sandbox.sh
./agents/hermes/verify-sandbox.sh
./agents/hermes/run-sandbox.sh   # keep in foreground
```

Users do not paste an inference API key; the chart generates it and OpenShell injects
Bearer auth. `create-sandbox.sh` strips `integrate.api.nvidia.com` from Hermes's upstream
policy first, since this recipe is on-premises-only.

## Example verify output

```text
[verify] Checking hermes --version (timeout 90s)...
hermes --version OK.
[verify] GET http://localhost:8642/health (timeout 90s)...
Health probe OK.
[verify] GET https://inference.local/v1/models (timeout 120s)...
models: llama3.2:3b
[verify] POST https://inference.local/v1/chat/completions
[verify] Example query: In one sentence, what is an AI agent sandbox?
[verify] Answer: An AI agent sandbox is a simulated environment where an AI agent
can interact and learn in a safe, controlled space.
OK: sandbox hermes-onprem reached https://inference.local for models and chat/completions (llama3.2:3b).
Runtime (optional foreground): ./agents/hermes/run-sandbox.sh
```

## Env vars

| Env var | Default | Purpose |
|---------|---------|---------|
| `HERMES_SANDBOX_IMAGE` | — (required) | Pushed image reference |
| `HERMES_SANDBOX_NAME` | `hermes-onprem` | OpenShell sandbox name |
| `OPENSHELL_PROVIDER_NAME` | `onprem-hermes` | OpenShell inference provider name |
| `HERMES_SANDBOX_CPU` / `HERMES_SANDBOX_MEMORY` | `2` / `4Gi` | Sandbox pod requests |
| `NEMOCLAW_TARGET_NODE` | unset (portable) | Pin the sandbox to a specific node |
| `VERIFY_HEALTH_TIMEOUT_SEC` / `VERIFY_CURL_TIMEOUT_SEC` | `90` / `120` | `verify-sandbox.sh` timeouts |

Health/smoke checks used by `create-sandbox.sh` / `verify-sandbox.sh` (from
[`agents/hermes/manifest.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/agents/hermes/manifest.yaml)):
`hermes --version` and `GET http://localhost:8642/health`.

## Notes

- Hermes forwards two ports inside the sandbox per its manifest: the dashboard on `18789`
  and the OpenAI-compatible API on `8642`. Neither is exposed by `create-sandbox.sh` today
  (it only uses `openshell sandbox exec` for the smoke checks above) — reaching the
  dashboard from outside the sandbox would need its own `kubectl port-forward` to the
  sandbox pod, which this recipe has not set up or validated.
- Hermes has no OpenClaw-style device pairing; its own web-UI auth is a Bearer token via
  `API_SERVER_KEY` (unrelated to the OpenShell-injected inference key) — not exercised by
  this recipe since the dashboard isn't exposed.
- OpenShell `0.0.85` leaves sandboxes idle (`sleep infinity`); `run-sandbox.sh` execs
  Hermes's entrypoint in the foreground and must stay attached — it does not auto-restart.

## Uninstall

Stop `run-sandbox.sh`. With the OpenShell port-forward still up:

```bash
openshell sandbox delete hermes-onprem
openshell provider delete onprem-hermes
openshell gateway remove nemoclaw-k8s
rm -r -- "${XDG_CONFIG_HOME:-${HOME}/.config}/openshell/gateways/nemoclaw-k8s/mtls"
```

Then, if no other sandboxes/agents are using the shared OpenShell gateway, see the recipe
root [Uninstall](../../README.md#uninstall) for `helm uninstall openshell` and the GPU chart.
