FROM golang:1.20-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git

# Copy go.mod and go.sum files
COPY go.mod ./
COPY go.sum ./
RUN go mod download

# Copy the source code
COPY . .

# Build the application for AMD64 architecture
RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o open-saves-aws .

# Create a minimal production image
FROM alpine:3.15

WORKDIR /app

# Install runtime dependencies including curl for downloading certificate
RUN apk add --no-cache ca-certificates curl

# Create config directory
RUN mkdir -p /etc/open-saves

# Download the AWS DocumentDB global certificate bundle
# Following AWS documentation: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
RUN curl -f -o /etc/ssl/certs/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    && ls -la /etc/ssl/certs/global-bundle.pem \
    && echo "Certificate downloaded successfully"

# Copy the binary from the builder stage
COPY --from=builder /app/open-saves-aws .

# Make the binary executable
RUN chmod +x /app/open-saves-aws

# Copy config file
COPY config/config.yaml /etc/open-saves/config.yaml

# Expose ports
EXPOSE 8080 8081

# Set the entry point
CMD ["/app/open-saves-aws"]
