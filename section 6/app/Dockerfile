# --- Stage 1: Build the static Go binary ---
# --platform=$BUILDPLATFORM runs the compiler natively on your laptop (fast),
# then Go cross-compiles for whatever --platform you asked docker to build.
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder

# Filled in automatically by `docker buildx build --platform ...`
ARG TARGETOS
ARG TARGETARCH

WORKDIR /build

# Copy the source code
COPY main.go .

# Compile the binary as fully static (disable CGO) for the target OS/CPU.
# -ldflags="-w -s" strips debugging symbols, reducing binary size
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -ldflags="-w -s" -o app main.go

# --- Stage 2: Deploy the binary in a minimal runtime environment ---
FROM alpine:3.19

WORKDIR /app

# Copy only the compiled binary from the builder stage
COPY --from=builder /build/app .

# Expose the application port
EXPOSE 8080

# Run the application
CMD ["./app"]
