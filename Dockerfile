ARG FROM=alpine
FROM $FROM as build
RUN apk add --no-cache go git musl-dev libjpeg-turbo-dev gcc
RUN go get github.com/gen2brain/cam2ip/cmd/cam2ip

FROM scratch
ARG GOARCH
ADD bin/${GOARCH}/kceu /kceu
COPY --from=build /root/go/bin/cam2ip /cam2ip
COPY --from=build /usr/lib/libjpeg.so* /usr/lib/
COPY --from=build /lib/*musl* /lib/
