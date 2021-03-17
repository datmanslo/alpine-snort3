#
# BUILD CONTAINER
# (Note that this is a multi-phase Dockerfile)
# To build run `docker build --rm -t snort3-alpine:latest`
# By default the latest code will be pulled from the SNort and libdaq master branches
# To build specific tagged releases add the appropriate --build args e.g.:
#  `docker build --build-arg BASE=alpine:3.11--build-arg SNORT_TAG=3.0.0-268 --build-arg DAQ_TAG=v3.0.0-alpha3 -t snort3-alpine:3.0.0-268`
#

ARG BASE=alpine:3.13.2

FROM $BASE as builder

ARG SNORT_TAG=master
ARG DAQ_TAG=master

ENV PREFIX_DIR=/usr/local
ENV BUILD_DIR=/tmp

# Install buildtime packages
RUN echo '@community https://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories && \
    echo '@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories && \
    apk add --no-cache \
    autoconf \
    automake \
    linux-headers \
    lcov@testing \
    wget \
    build-base \
    git \
    cmake \
    bison \
    flex \
    cppcheck \
    cpputest \
    flatbuffers-dev \
    hwloc-dev@community \
    libdnet-dev \
    libpcap-dev \
    libtirpc-dev \
    libmnl-dev \
    luajit-dev \
    libressl-dev \
    libtool \
    libnetfilter_queue-dev \
    zlib-dev \
    pcre-dev \
    libuuid \
    xz-dev

# BUILD Daq

WORKDIR $BUILD_DIR
RUN git clone -b ${DAQ_TAG} --depth 1 https://github.com/snort3/libdaq.git

WORKDIR $BUILD_DIR/libdaq
RUN ./bootstrap && \
    ./configure --prefix=${PREFIX_DIR} && \
    make -j$(nproc) install

# BUILD Snort
WORKDIR $BUILD_DIR
RUN git clone  -b ${SNORT_TAG} --depth 1 https://github.com/snort3/snort3.git

WORKDIR $BUILD_DIR/snort3
RUN CXX_FLAGS="-fno-rtti O3" ./configure_cmake.sh \
   --prefix=${PREFIX_DIR} \
   --build-type=MinSizeRel \
   --disable-gdb \
   --enable-tsc-clock \
   --disable-static-daq \
   --disable-docs \
   --enable-large-pcap

WORKDIR $BUILD_DIR/snort3/build
RUN make VERBOSE=1 -j$(nproc) install

#
# RUNTIME CONTAINER
#
FROM $BASE

ENV PREFIX_DIR=/usr/local
WORKDIR ${PREFIX_DIR}

# Install runtime packags
RUN echo '@community https://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories

# Prep APK for installing packages
RUN apk add --no-cache  \
    flatbuffers \
    hwloc@community \
    libdnet \
    luajit \
    libressl \
    libpcap \
    libmnl \
    libnetfilter_queue \
    pcre \
    libtirpc \
    musl \
    libstdc++ \
    libuuid \
    zlib \
    xz

# Copy the build artifacts from the build container to the runtime file system
COPY --from=builder ${PREFIX_DIR}/etc/ ${PREFIX_DIR}/etc/
COPY --from=builder ${PREFIX_DIR}/lib/ ${PREFIX_DIR}/lib/
COPY --from=builder ${PREFIX_DIR}/lib64/ ${PREFIX_DIR}/lib64/
COPY --from=builder ${PREFIX_DIR}/bin/ ${PREFIX_DIR}/bin/

WORKDIR /
RUN snort --version

