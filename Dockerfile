FROM scratch
ARG ARCH
ADD bin/${ARCH}/kceu /kceu
ADD bin/${ARCH}/mjpeg /mjpeg
