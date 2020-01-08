ARG FROM=golang:alpine
FROM $FROM as build
RUN apk add --no-cache git musl-dev libjpeg-turbo-dev gcc
RUN GODEBUG=gccheckmark=1 go get github.com/gen2brain/cam2ip/cmd/cam2ip
RUN echo $GOPATH

FROM scratch
ARG GOARCH
ADD bin/${GOARCH}/kceu /kceu
COPY --from=build /go/bin/cam2ip /cam2ip
COPY --from=build /usr/lib/libjpeg.so* /usr/lib/
COPY --from=build /lib/*musl* /lib/
