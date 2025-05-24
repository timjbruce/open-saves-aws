FROM --platform=linux/amd64 golang:1.20-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git

# Copy go.mod and go.sum files
COPY go.mod ./
COPY go.sum ./
RUN go mod download

# Copy the source code
COPY . .

# Build the application specifically for AMD64
RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o open-saves-aws .

# Create a minimal production image
FROM --platform=linux/amd64 alpine:3.15

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Create config directory
RUN mkdir -p /etc/open-saves

# Copy the binary from the builder stage
COPY --from=builder /app/open-saves-aws .

# Make the binary executable
RUN chmod +x /app/open-saves-aws

# Copy config file
COPY config/config.yaml /etc/open-saves/config.yaml

# Expose ports
EXPOSE 8080 8081

# Set the entry point
ENTRYPOINT ["/app/open-saves-aws"]
CMD ["--config", "/etc/open-saves/config.yaml"]
