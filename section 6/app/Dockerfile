# --- Stage 1: Build the static Go binary ---
FROM golang:1.22-alpine AS builder

WORKDIR /build

# Copy the source code
COPY main.go .

# Compile the binary as fully static (disable CGO, compile for linux)
# -ldflags="-w -s" strips debugging symbols, reducing binary size
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o app main.go

# --- Stage 2: Deploy the binary in a minimal runtime environment ---
FROM alpine:3.19

WORKDIR /app

# Copy only the compiled binary from the builder stage
COPY --from=builder /build/app .

# Expose the application port
EXPOSE 8080

# Run the application
CMD ["./app"]
