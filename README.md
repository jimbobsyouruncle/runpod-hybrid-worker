# RunPod Hybrid Worker

This repository builds and maintains the cloud inference plane for the Hybrid AI project. It compiles a custom vLLM Docker container tailored for RunPod GPU instances, enforcing strict network isolation, zero-trace logging, and automated cost controls.

## Why a Custom Image?

Official vLLM Docker images hardcode `vllm serve` as their default `ENTRYPOINT`. Passing custom startup scripts directly via RunPod's UI causes vLLM to parse the script as compilation flags, leading to immediate boot crashes. 

This repository solves that by building a custom image via GitHub Actions (`ghcr.io/YOUR_USERNAME/runpod-hybrid-worker:latest`). The custom image overrides the entrypoint to run `start.sh` as PID 1, orchestrating Tailscale, OpenSSH, and the GPU watchdog *before* binding the vLLM engine.

---

## Core Features

1. **Private Mesh Networking:** Connects to your Tailscale mesh (`100.x.x.x`) using userspace networking. The model and SSH daemon are never exposed to the public internet (RunPod public ports are left completely blank).
2. **Automated Cost Watchdog:** A background loop samples GPU utilization every 5 seconds. After 15 consecutive minutes of 0% utilization, the pod automatically calls the RunPod GraphQL API to terminate itself, preventing runaway billing.
3. **Secure SSH Injection:** Reads RunPod's account-injected `$PUBLIC_KEY` variable and spins up an internal `sshd` service, allowing direct SSH access over Tailscale.
4. **Zero-Trace Logging:** Launches vLLM with request, token, and stats logging explicitly disabled to preserve privacy.

---

## Deployment Guide

### 1. Build and Publish the Image

1. **Fork or Clone:** Push this repository to your own GitHub account.
2. **Trigger Build:** The included `.github/workflows/build.yml` automatically builds the Docker image upon pushing to `main`. Wait for the GitHub Actions pipeline to complete.
3. **Make Public:** Go to your GitHub repository homepage → **Packages** (right sidebar) → click your image → **Package Settings** → **Danger Zone** → **Change package visibility** to **Public**.

### 2. Gather Required Keys

* **Tailscale Auth Key (`tskey-auth-...`):** Generate a Reusable, Ephemeral, Pre-approved key from your Tailscale admin console.
* **RunPod API Key (`rpa_...`):** Needed by the watchdog to stop the pod when idle.
* **RunPod SSH Key:** Ensure your standard public SSH key (`ssh-ed25519 AAA...`) is saved in your main RunPod Account Settings. RunPod injects this automatically.

### 3. Deploy the Pod on RunPod

In the RunPod console, click **Deploy Pod** and use the following configuration:

| Setting | Value | Notes |
|---|---|---|
| **Container Image** | `ghcr.io/YOUR_USERNAME/runpod-hybrid-worker:latest` | Use your public GHCR URL. |
| **Start Command** | *Leave Empty* | The custom `ENTRYPOINT` handles execution. |
| **Container Disk** | `20 GB` | Holds the OS layer only. |
| **Volume Disk** | `100 GB` at `/workspace` | Caches model weights to reduce cold starts from 10+ mins to 2 mins. |
| **HTTP Ports** | *Leave Empty* | Critical. Bypasses public load balancers. |
| **TCP Ports** | *Leave Empty* | Critical. SSH and vLLM run via Tailscale. |

### 4. Environment Variables

Add these to your RunPod template:

| Variable | Value | Required |
|---|---|---|
| `TAILSCALE_AUTH_KEY` | `tskey-auth-...` | **Yes** — required to join the private mesh. |
| `RUNPOD_API_KEY` | `rpa_...` | **Yes** — enables the automated cost watchdog. |
| `VLLM_API_KEY` | `sk-vllm-...` | Optional — secures the `/v1` endpoint. |
| `VLLM_MODEL` | `Qwen/Qwen2.5-Coder-32B-Instruct-AWQ` | Optional — overrides default model. |
| `IDLE_MINUTES` | `15` | Optional — sets the watchdog grace period. |
| `MAX_MODEL_LEN` | `16384` | Optional — context window size. |
| `GPU_MEM_UTIL` | `0.92` | Optional — lower to `0.85` if OOM errors occur. |
| `TS_HOSTNAME` | `runpod-worker` | Optional — the name registered in Tailscale. |

*(Note: RunPod automatically injects `RUNPOD_POD_ID` and `PUBLIC_KEY` in the background).*

---

## Verification

Start the pod manually once. Check the RunPod console logs for the following sequence:

```text
[start.sh] Injecting RunPod public SSH keys...
[start.sh] SSH daemon started. Accessible via Tailscale on port 22.
[start.sh] Starting tailscaled (userspace-networking)...
[start.sh] Mesh address acquired: 100.x.x.x
[start.sh] Arming idle watchdog: 15 min @ 0% GPU -> podStop
[start.sh] Launching vLLM -- model=Qwen/... tp=1 port=8000
