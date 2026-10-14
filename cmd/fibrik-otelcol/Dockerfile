# Multi-arch build of fibrik-otelcol. Go cross-compiles on the build host, so
# no emulation is needed for arm64.
FROM --platform=$BUILDPLATFORM golang:1.27.2 AS build
ARG TARGETOS TARGETARCH
ARG OCB_VERSION=v0.163.0
RUN go install go.opentelemetry.io/collector/cmd/builder@${OCB_VERSION}
WORKDIR /src
COPY builder-config.yaml .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} builder --config builder-config.yaml

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /src/_build/fibrik-otelcol /fibrik-otelcol
USER 65532:65532
ENTRYPOINT ["/fibrik-otelcol"]
