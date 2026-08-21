<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# OpenClaw

Default agent for this recipe. Gateway-based agent with a plugin ecosystem
([openclaw.ai](https://openclaw.ai)); upstream source at
[`NVIDIA/NemoClaw/agents/openclaw`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/openclaw)
(image still builds from the repo root `Dockerfile` — see that manifest's `_legacy_paths`).

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

### 2. Build and push the OpenClaw sandbox image

```bash
export NEMOCLAW_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-openclaw-k8s:v0.0.104
./agents/openclaw/build-sandbox-image.sh
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
export NEMOCLAW_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-openclaw-k8s:v0.0.104
export INFERENCE_MODEL=llama3.2:3b   # must match the GPU chart model
./agents/openclaw/create-sandbox.sh
./agents/openclaw/verify-sandbox.sh
./agents/openclaw/run-sandbox.sh   # keep in foreground
```

Users do not paste an inference API key; the chart generates it and OpenShell injects
Bearer auth. `create-sandbox.sh` strips `integrate.api.nvidia.com` from OpenClaw's
upstream policy first, since this recipe is on-premises-only.

## Example verify output

```text
[verify] openclaw plugins inspect nemoclaw
[verify] GET https://inference.local/v1/models (timeout 120s)...
models: llama3.2:3b
[verify] POST https://inference.local/v1/chat/completions
[verify] Example query: In one sentence, what is an AI agent sandbox?
[verify] Answer: An AI agent sandbox is a simulated environment where an AI agent
can interact and learn in a safe, controlled space.
OK: sandbox nemoclaw-onprem reached https://inference.local for models and chat/completions (llama3.2:3b).
Runtime (optional foreground): ./agents/openclaw/run-sandbox.sh
```

## Env vars

| Env var | Default | Purpose |
|---------|---------|---------|
| `NEMOCLAW_SANDBOX_IMAGE` | — (required) | Pushed image reference |
| `NEMOCLAW_SANDBOX_NAME` | `nemoclaw-onprem` | OpenShell sandbox name |
| `OPENSHELL_PROVIDER_NAME` | `onprem-ollama` | OpenShell inference provider name |
| `NEMOCLAW_SANDBOX_CPU` / `NEMOCLAW_SANDBOX_MEMORY` | `2` / `4Gi` | Sandbox pod requests |
| `NEMOCLAW_TARGET_NODE` | unset (portable) | Pin the sandbox to a specific node |

Health/smoke check used by `verify-sandbox.sh`: `openclaw plugins inspect nemoclaw --json`.

## Notes

- OpenShell `0.0.85` leaves sandboxes idle (`sleep infinity`); `run-sandbox.sh` execs
  OpenClaw's entrypoint in the foreground and must stay attached — it does not auto-restart.
- Combined topology (privilege drop + OpenClaw's Node-based tooling) may require capabilities
  like `SYS_ADMIN` / `NET_ADMIN` in a restrictive admission policy — check your cluster's
  Pod Security admission before assuming a clean create.
- This is the most exercised agent in this recipe; still, the on-premises 8×H100 path is
  [not yet independently validated](../../README.md#validated-hardware) end-to-end.

## Uninstall

Stop `run-sandbox.sh`. With the OpenShell port-forward still up:

```bash
openshell sandbox delete nemoclaw-onprem
openshell provider delete onprem-ollama
openshell gateway remove nemoclaw-k8s
rm -r -- "${XDG_CONFIG_HOME:-${HOME}/.config}/openshell/gateways/nemoclaw-k8s/mtls"
```

Then, if no other sandboxes/agents are using the shared OpenShell gateway, see the recipe
root [Uninstall](../../README.md#uninstall) for `helm uninstall openshell` and the GPU chart.
