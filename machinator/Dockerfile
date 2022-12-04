# syntax=docker/dockerfile:1.4
FROM golang:1.19-bullseye as builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY *.go *.sh *.html ./
RUN CGO_ENABLED=0 go build -ldflags="-s"

# NB we use the bullseye-slim (instead of scratch) image so we can enter the container to execute bash etc.
FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y ipmitool && rm -rf /var/lib/apt/lists/*
ADD --chmod=755 https://dl.k8s.io/release/v1.25.4/bin/linux/amd64/kubectl /usr/local/bin/kubectl
ADD --chmod=755 https://github.com/siderolabs/talos/releases/download/v1.2.7/talosctl-linux-amd64 /usr/local/bin/talosctl
COPY --from=builder /app/machinator .
EXPOSE 8000
ENTRYPOINT ["/machinator"]
