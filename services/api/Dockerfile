FROM golang:1.27.4-bookworm AS builder
WORKDIR /src
COPY services/api/go.mod ./go.mod
RUN go mod download
COPY services/api/ ./
ARG APP=api
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/${APP}

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=builder /out/app /app
EXPOSE 5050
ENTRYPOINT ["/app"]
