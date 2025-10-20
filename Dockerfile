
# --- Build stage ---
FROM rust:1.90-slim AS builder
WORKDIR /app

# Add the musl target for static linking
RUN apt-get update && apt-get install -y musl-tools build-essential pkg-config && rm -rf /var/lib/apt/lists/*
RUN rustup target add x86_64-unknown-linux-musl

# Copy manifest and lock so dependencies can be cached
COPY Cargo.toml Cargo.lock ./

# Create a dummy source file to ensure dependencies build ahead of time
# RUN mkdir src && echo "fn main() { println!(\"dummy1\"); }" > src/main.rs
# RUN cargo build --release --target x86_64-unknown-linux-musl
# RUN rm -rf src

# Now copy actual source code
COPY src ./src
# If you have other folders (e.g., migrations, templates), copy them here as well
# COPY migrations ./migrations

# Build the real binary (replace `myserver` with your binary name)
RUN cargo build --release --target x86_64-unknown-linux-musl --bin rust_hello 

# --- Runtime stage ---
FROM scratch
# If your binary uses TLS / OpenSSL / HTTPS you may need certificates:
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy the statically-linked binary
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/rust_hello /rust_hello

# Expose port (adjust as needed)
EXPOSE 3000

ENTRYPOINT ["/rust_hello"]
