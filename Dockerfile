# --- Build stage ---
FROM rust:1.90-slim AS builder
WORKDIR /app

# Install build essentials, musl, and cargo-chef
RUN apt-get update && apt-get install -y musl-tools build-essential pkg-config && \
    rm -rf /var/lib/apt/lists/*
RUN rustup target add x86_64-unknown-linux-musl
# Install cargo-chef
RUN cargo install cargo-chef

# --- Dependency caching stage ---
# Copy manifests to compute dependency plan
COPY Cargo.toml Cargo.lock ./
# This creates a 'recipe' of just your dependencies
RUN cargo chef prepare --recipe-path recipe.json

# Build (cook) dependencies. This layer is cached.
RUN cargo chef cook --release --target x86_64-unknown-linux-musl --recipe-path recipe.json

# --- Application build stage ---
# Copy actual source code
COPY src ./src
# COPY migrations ./migrations
ENV RUSTFLAGS="-C target-feature=+crt-static"
# Build the real binary, leveraging cached dependencies
RUN cargo build --release --target x86_64-unknown-linux-musl --bin rust_hello --locked

# --- Runtime stage ---
# Use distroless/static as a more secure alternative to scratch
# It's tiny but includes basics like a non-root user and timezone data
FROM gcr.io/distroless/static-debian12
# Alpine needs these to run musl binaries
# RUN apk add --no-cache musl-dev libc-utils

# Copy the statically-linked binary
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/rust_hello /rust_hello

# Expose port (adjust as needed)
EXPOSE 3000

# 'distroless/static' images run as 'nonroot' (UID 65532) by default,
# so the 'USER' command is not needed.
ENTRYPOINT ["/rust_hello"]
