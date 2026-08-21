<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# Agents

Pick one CPU-only agent to run inside the OpenShell sandbox. Each subfolder here mirrors
[`NVIDIA/NemoClaw/agents`](https://github.com/NVIDIA/NemoClaw/tree/main/agents) and is
self-contained: build the image, create the sandbox, verify it, then run it. All three
route inference identically — through OpenShell's `https://inference.local/v1` proxy to
the GPU inference pods this recipe deploys (`../README.md#inference-runtimes`) — so the
GPU HPA and monitoring stack are unaffected by which agent you choose.

| | [OpenClaw](openclaw/) | [Hermes](hermes/) | [Deep Agents Code](langchain-deepagents-code/) |
|---|---|---|---|
| Upstream | [`agents/openclaw`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/openclaw) | [`agents/hermes`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/hermes) | [`agents/langchain-deepagents-code`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/langchain-deepagents-code) |
| Shape | Long-running gateway + dashboard | Long-running gateway + dashboard | Terminal harness (one-shot per prompt) |
| Interactive entry | `openclaw tui` | `hermes` | `dcode` |
| Headless / scripted entry | gateway API (dashboard :18789) | gateway API (:8642), dashboard :18789 | `dcode -n "<prompt>"` |
| Health surface | `http://localhost:18789/` | `http://localhost:8642/health` | none (`dcode --version` + config check) |
| Runtime | `run-sandbox.sh` (foreground, keep terminal open) | `run-sandbox.sh` (foreground, keep terminal open) | `run-prompt.sh "<prompt>"` (one-shot, exits) |
| Default sandbox name | `nemoclaw-onprem` | `hermes-onprem` | `deepagents-onprem` |

Every agent folder has the same four scripts (Deep Agents Code swaps `run-sandbox.sh` for
`run-prompt.sh` since it has no gateway to keep in the foreground):

| Script | Purpose |
|--------|---------|
| `build-sandbox-image.sh` | Clone the pinned `NVIDIA/NemoClaw` release and build/push this agent's sandbox image |
| `create-sandbox.sh` | Wire OpenShell's inference route to the chart's GPU inference pods, then create the sandbox (no GPU) |
| `verify-sandbox.sh` | Confirm the sandbox can reach `https://inference.local` and the agent binary itself is healthy |
| `run-sandbox.sh` / `run-prompt.sh` | Start (or invoke) the agent |

## Choosing an agent

Only run one agent's sandbox at a time unless you deliberately want to compare them
side by side (each uses its own `*_SANDBOX_NAME` default and OpenShell provider name, so
running more than one concurrently is possible but untested by this recipe).

```bash
# OpenClaw (default, most exercised by this recipe)
export NEMOCLAW_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-openclaw-k8s:v0.0.104
./agents/openclaw/build-sandbox-image.sh
./agents/openclaw/create-sandbox.sh
./agents/openclaw/verify-sandbox.sh
./agents/openclaw/run-sandbox.sh   # keep in foreground

# Hermes
export HERMES_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-hermes-k8s:v0.0.104
./agents/hermes/build-sandbox-image.sh
./agents/hermes/create-sandbox.sh
./agents/hermes/verify-sandbox.sh
./agents/hermes/run-sandbox.sh   # keep in foreground

# Deep Agents Code
export DEEPAGENTS_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-deepagents-k8s:v0.0.104
./agents/langchain-deepagents-code/build-sandbox-image.sh
./agents/langchain-deepagents-code/create-sandbox.sh
./agents/langchain-deepagents-code/verify-sandbox.sh
./agents/langchain-deepagents-code/run-prompt.sh "Explain this repository in one sentence."
```

## Shared policy notes

Each agent's `create-sandbox.sh` clones the pinned `NVIDIA/NemoClaw` release and passes
that agent's own upstream OpenShell sandbox policy file to `openshell sandbox create
--policy`:

- OpenClaw: `nemoclaw-blueprint/policies/openclaw-sandbox.yaml`
- Hermes: `agents/hermes/policy-additions.yaml`
- Deep Agents Code: `agents/langchain-deepagents-code/policy-additions.yaml`

Despite the `policy-additions.yaml` filename, both files are complete, self-contained
OpenShell policies (not deltas merged onto another file) — verified against the upstream
schema (`version`, `filesystem_policy`, `landlock`, `process`, `network_policies`) before
this recipe used them the same way it already used `openclaw-sandbox.yaml`.

OpenClaw's and Hermes' upstream policies both grant `integrate.api.nvidia.com` as a
default inference endpoint; `create-sandbox.sh` removes it after sandbox creation because
this recipe is on-premises-only (see each `create-sandbox.sh` for the exact
`openshell policy update --remove-endpoint` step). Deep Agents Code's policy does not
grant that endpoint in the first place, so its script only verifies the endpoint is
absent.

Not yet independently validated end-to-end against a live cluster (see
`../README.md#validated-hardware`); please file an issue with anything you find while
trying Hermes or Deep Agents Code on `dgx02`-class (8×H100) hardware.
