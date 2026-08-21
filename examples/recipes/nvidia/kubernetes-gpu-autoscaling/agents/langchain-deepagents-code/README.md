<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# Deep Agents Code

Terminal coding agent built on the
[Deep Agents SDK](https://docs.langchain.com/oss/python/deepagents/code/overview);
upstream source at
[`NVIDIA/NemoClaw/agents/langchain-deepagents-code`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/langchain-deepagents-code).

**This agent has no long-running gateway or dashboard** (`runtime.kind: terminal` in its
manifest) — it is invoked headlessly, one prompt at a time, via `dcode -n "<prompt>"`.
There is intentionally no `run-sandbox.sh` here; use `run-prompt.sh` instead. This is the
biggest shape difference from OpenClaw/Hermes in this recipe — read
[Notes](#notes) before assuming feature parity.

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

### 2. Build and push the Deep Agents Code sandbox image

```bash
export DEEPAGENTS_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-deepagents-k8s:v0.0.104
./agents/langchain-deepagents-code/build-sandbox-image.sh
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

### 4. Create and verify the sandbox, then run a prompt

```bash
export DEEPAGENTS_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-deepagents-k8s:v0.0.104
export INFERENCE_MODEL=llama3.2:3b   # must match the GPU chart model
./agents/langchain-deepagents-code/create-sandbox.sh
./agents/langchain-deepagents-code/verify-sandbox.sh
./agents/langchain-deepagents-code/run-prompt.sh "Explain this repository in one sentence."
```

Users do not paste an inference API key; the chart generates it and OpenShell injects
Bearer auth. Unlike OpenClaw/Hermes, `create-sandbox.sh` does **not** need to strip
`integrate.api.nvidia.com` — Deep Agents Code's own upstream policy never grants it.

For an interactive session instead of one-shot prompts, use a terminal that supports a
TTY directly with OpenShell (bypasses `run-prompt.sh` entirely):

```bash
openshell sandbox exec -n "${DEEPAGENTS_SANDBOX_NAME:-deepagents-onprem}" -- dcode
```

## Example verify output

```text
[verify] Checking dcode --version (timeout 30s)...
dcode --version OK.
[verify] Checking config.toml was generated (timeout 30s)...
config.toml OK.
[verify] GET https://inference.local/v1/models (timeout 120s)...
models: llama3.2:3b
[verify] dcode -n (headless) — this is the real agent binary, not a curl probe (timeout 120s)
[verify] Example query: In one sentence, what is an AI agent sandbox?
[verify] Answer: An AI agent sandbox is a simulated environment where an AI agent
can interact and learn in a safe, controlled space.
OK: sandbox deepagents-onprem reached https://inference.local and dcode answered a real prompt (llama3.2:3b).
Deep Agents Code has no long-running gateway; run one-shot prompts with:
  ./agents/langchain-deepagents-code/run-prompt.sh "your prompt here"
```

## Env vars

| Env var | Default | Purpose |
|---------|---------|---------|
| `DEEPAGENTS_SANDBOX_IMAGE` | — (required) | Pushed image reference |
| `DEEPAGENTS_SANDBOX_NAME` | `deepagents-onprem` | OpenShell sandbox name |
| `OPENSHELL_PROVIDER_NAME` | `onprem-deepagents` | OpenShell inference provider name |
| `DEEPAGENTS_SANDBOX_CPU` / `DEEPAGENTS_SANDBOX_MEMORY` | `2` / `4Gi` | Sandbox pod requests |
| `NEMOCLAW_TARGET_NODE` | unset (portable) | Pin the sandbox to a specific node |
| `VERIFY_SMOKE_TIMEOUT_SEC` / `VERIFY_CURL_TIMEOUT_SEC` / `VERIFY_DCODE_TIMEOUT_SEC` | `30` / `120` / `120` | `verify-sandbox.sh` timeouts |

Smoke checks used by `create-sandbox.sh` / `verify-sandbox.sh` (from this agent's own
[`manifest.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/agents/langchain-deepagents-code/manifest.yaml)
`runtime.smoke_commands`): `dcode --version`, a `config.toml` existence check, then a real
`dcode -n "<prompt>"` call through `https://inference.local`.

## Notes

- No dashboard, no gateway process, no port to forward — `dcode` runs, answers, and exits
  for every invocation (`headless_command: "dcode -n"` in the manifest). This means there is
  nothing for the HPA/monitoring stack to distinguish as "the agent is up" beyond the
  sandbox pod itself being Ready; you cannot poll a `/health` endpoint the way you can for
  OpenClaw/Hermes.
- Every `run-prompt.sh` call is a fresh `openshell sandbox exec`; there is no persistent
  agent session/memory across calls beyond whatever `dcode` itself persists under
  `/sandbox/.deepagents` inside the sandbox.
- The upstream policy (`policy-additions.yaml`) grants `github.com` / `api.github.com` /
  `raw.githubusercontent.com` by default (read/write for git, read-only for raw file
  fetches) since Deep Agents Code is a coding agent — this is broader default network
  access than OpenClaw/Hermes get out of the box. Review it if that's not desired for your
  environment.
- `landlock.compatibility: strict` in this agent's policy (vs. `best_effort` for
  OpenClaw/Hermes) means sandbox creation **fails closed** if the kernel/workspace mount
  cannot enforce the declared read-only paths, rather than silently degrading.

## Uninstall

No foreground process to stop — just delete the sandbox. With the OpenShell port-forward
still up:

```bash
openshell sandbox delete deepagents-onprem
openshell provider delete onprem-deepagents
openshell gateway remove nemoclaw-k8s
rm -r -- "${XDG_CONFIG_HOME:-${HOME}/.config}/openshell/gateways/nemoclaw-k8s/mtls"
```

Then, if no other sandboxes/agents are using the shared OpenShell gateway, see the recipe
root [Uninstall](../../README.md#uninstall) for `helm uninstall openshell` and the GPU chart.
