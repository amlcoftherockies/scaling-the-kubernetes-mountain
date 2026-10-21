# --- Stage 1: Build the static Go binary ---
# --platform=$BUILDPLATFORM runs the compiler natively on your laptop (fast),
# then Go cross-compiles for whatever --platform you asked docker to build.
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder

# Filled in automatically by `docker buildx build --platform ...`
ARG TARGETOS
ARG TARGETARCH

WORKDIR /build

# Copy source code (in larger Go apps with go.mod/go.sum, copy go.mod & go.sum
# first and run `go mod download` so dependency layers stay cached!)
COPY main.go .

# Compile the binary as fully static (disable CGO) for the target OS/CPU.
# -ldflags="-w -s" strips DWARF/symbol tables, shrinking the binary by ~30%.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -ldflags="-w -s" -o app main.go

# --- Stage 2: Deploy the binary in a minimal runtime environment ---
FROM alpine:3.19

# Create an unprivileged non-root user (UID 65532) for container hardening
RUN adduser -D -u 65532 appuser

WORKDIR /app

# Copy only the compiled binary from the builder stage
COPY --from=builder /build/app .

# Run as non-root UID (satisfies Kubernetes PodSecurity runAsNonRoot!)
USER 65532:65532

# Expose the application port
EXPOSE 8080

# Run the application
CMD ["./app"]
