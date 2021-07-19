FROM golang:1.16-buster as builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY *.go *.sh *.html ./
RUN CGO_ENABLED=0 go build -ldflags="-s"

# NB we use the buster-slim (instead of scratch) image so we can enter the container to execute bash etc.
FROM debian:buster-slim
ADD --chmod=755 https://dl.k8s.io/release/v1.21.0/bin/linux/amd64/kubectl /usr/local/bin/kubectl
# TODO remove the next line after https://github.com/moby/buildkit/pull/2171 lands in a docker release.
RUN chmod 755 /usr/local/bin/kubectl
ADD --chmod=755 https://github.com/talos-systems/talos/releases/download/v0.11.2/talosctl-linux-amd64 /usr/local/bin/talosctl
# TODO remove the next line after https://github.com/moby/buildkit/pull/2171 lands in a docker release.
RUN chmod 755 /usr/local/bin/talosctl
COPY --from=builder /app/machinator .
EXPOSE 8000
ENTRYPOINT ["/machinator"]