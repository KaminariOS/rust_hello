# rust_hello

`rust_hello` is a lightweight Axum-based web service that reports how long a Kubernetes Service has been running and how many pod endpoints are currently available. It is designed for quick status pages, such as self-hosted homepages, and degrades gracefully when it cannot talk to a cluster.

## Motivation
Just want to push the limit of a practical Rust container and see how small it can get. 

## Considerations
To build a minimal image, static linking is necessary.

The Axum server itself does not require TLS and in actual services TLS usually terminates at the API gateway like Ngnix.

However, `kube-rs` needs TLS to talk to K8S. Therefore, use rust-tls.

Instead of the `scatch` base image, use `distroless`: just like scratch, but run as non-root and timezone data is included.

## Features
- Minimal image size: 10.4 MB 
- Minimal runtime memory footprint: 1 MB
- Computes uptime for a named Kubernetes Service by reading its `creationTimestamp`.
- Counts ready endpoints via the Kubernetes Endpoints API to highlight replica availability.
- Renders a minimal HTML page suitable for dashboards or homepages.
- Falls back to informative error messaging when run outside a cluster or without credentials.
- Ships with a distroless-compatible Dockerfile, Helm chart, and helper script for deployments.


## Getting Started
### Prerequisites
- Rust toolchain (2024 edition support; install via `rustup` or `nix develop`).
- Access to a Kubernetes cluster if you want live data. The binary still runs without one.

### Run Locally
```bash
cargo run
```

By default the server listens on `0.0.0.0:3000`. If your kubeconfig is available (e.g., `~/.kube/config`), the application uses it automatically. Otherwise it logs a warning and serves an error page instead of uptime data.

### Configuration
- `SERVICE_NAME` (default: `rust-hello`) – target Service to inspect.
- `POD_NAMESPACE` – overrides the namespace detection. If unset, the app reads `/var/run/secrets/kubernetes.io/serviceaccount/namespace` and falls back to `default`.

## Container Image
Build a static container image using the provided multi-stage Dockerfile:
```bash
podman build -t rust-hello:local .
podman run --rm -p 3000:3000 -e SERVICE_NAME=your-service rust-hello:local
```
### Image size:
| Commit | Description | Size(MB) |
| :------- | :------: | -------: |
| a71d829  |  Regular Cargo.toml | 14.4 |
| 0c64813  |  Optimized Cargo.toml  |  10.4  |

Symbols: 1MB.

The final stage is based on `gcr.io/distroless/static-debian12`, runs as a non-root user, and exposes port `3000`.

## Kubernetes Deployment
- Helm chart: `charts/rust-hello`
- Helper script: `deploy.sh` (builds with Podman, pushes to a registry, and upgrades the Helm release)

Quick deploy (adjust registry and namespace inside `deploy.sh` first):
```bash
./deploy.sh
```

Alternatively, install the chart manually:
```bash
helm upgrade --install rust-hello ./charts/rust-hello \
  --namespace default \
  --set image.repository=docker.io/you/rust-hello \
  --set image.tag=latest
```

## Development with Nix
This repository ships a `flake.nix` that sets up a reproducible toolchain and pre-commit hooks:
```bash
nix develop
```

The shell prints toolchain versions on entry and ensures `rustfmt`, `clippy`, and other helpful Cargo tools are available.

## Project Layout
- `src/main.rs` – service implementation and Kubernetes integration.
- `Dockerfile` – static, distroless build pipeline using `cargo-chef`.
- `deploy.sh` – Podman + Helm automation script.
- `charts/rust-hello` – Helm chart templates and default values.
- `flake.nix` – reproducible development environment (optional).
- `TODO.md` 

## Status & Next Steps
The service currently focuses on uptime reporting. Enhancements on the roadmap (see `TODO.md`) include reducing image size and improving replica handling.

