ARG TARGETARCH=amd64
# --- Build stage ---
# A re-taggeed version of ghcr.io/rust-cross/rust-musl-cross
# See https://github.com/rust-cross/rust-musl-cross/issues/133#issuecomment-3449162968
FROM --platform=$BUILDPLATFORM docker.io/allheil/rust-musl-cross:$TARGETARCH AS builder
WORKDIR /app

# Install cargo-chef
# Use native CARGO_BUILD_TARGET
# --locked to make this layer deterministic 
RUN env -u CARGO_BUILD_TARGET cargo install --locked cargo-chef

# --- Dependency caching stage ---
# Copy manifests to compute dependency plan
COPY Cargo.toml Cargo.lock ./
# This creates a 'recipe' of just your dependencies
RUN cargo chef prepare --recipe-path recipe.json
#
RUN cargo chef cook --release --recipe-path recipe.json

# --- Application build stage ---
# Copy actual source code
COPY src ./src

RUN cargo build --release --bin rust_hello  

# --- Runtime stage ---
# Use distroless/static as a more secure alternative to scratch
# It's tiny but includes basics like a non-root user and timezone data
FROM  --platform=$TARGETPLATFORM gcr.io/distroless/static-debian12
COPY --from=builder /app/target/*/release/rust_hello /rust_hello

# Expose port (adjust as needed)
EXPOSE 3000

# 'distroless/static' images run as 'nonroot' (UID 65532) by default,
# so the 'USER' command is not needed.
ENTRYPOINT ["/rust_hello"]
