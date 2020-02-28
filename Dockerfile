#
# BUILD CONTAINER
# (Note that this is a multi-phase Dockerfile)
# To build run `docker build --rm -t snort3-alpine:latest`
# By default the latest code will be pulled from the SNort and libdaq master branches
# To build specific tagged releases add the appropriate --build args e.g.:
#  `docker build --build-arg BASE=alpine:3.11--build-arg SNORT_TAG=3.0.0-268 --build-arg DAQ_TAG=v3.0.0-alpha3 -t snort3-alpine:3.0.0-268`
#

ARG BASE=alpine:3.11.3

FROM $BASE as builder

ARG SNORT_TAG=master
ARG DAQ_TAG=master

ENV PREFIX_DIR=/usr/local
ENV BUILD_DIR=/tmp

# Update APK adding the @testing repo for hwloc (as of Alpine v3.7)
RUN echo '@testing http://nl.alpinelinux.org/alpine/edge/testing' >>/etc/apk/repositories && \
    apk add --no-cache \
    autoconf \
    automake \
    linux-headers \
    wget \
    build-base \
    git \
    cmake \
    bison \
    flex \
    lcov@testing \
    cppcheck \
    cpputest \
    # Libraries
    flatbuffers-dev@testing \
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

# The Alpine hwloc on testing is not reliable from a build perspective.
# So, lets just build it ourselves.
#
WORKDIR $BUILD_DIR
RUN wget https://download.open-mpi.org/release/hwloc/v2.0/hwloc-2.0.3.tar.gz &&\
    tar zxvf hwloc-2.0.3.tar.gz
WORKDIR $BUILD_DIR/hwloc-2.0.3
RUN ./configure --prefix=${PREFIX_DIR} && \
    make && \
    make install

# BUILD Daq on alpine:
# Note that this is the old DAQ and will eventually be replaced w/ DAQ-NG

WORKDIR $BUILD_DIR
RUN git clone -b ${DAQ_TAG} --depth 1 https://github.com/snort3/libdaq.git
WORKDIR $BUILD_DIR/libdaq

# BUILD daq
RUN ./bootstrap && \
    ./configure --prefix=${PREFIX_DIR} && \
    make && \
    make install

ARG SNORT_TAG=master
ARG DAQ_TAG=master
# BUILD Snort on alpine
WORKDIR $BUILD_DIR
RUN git clone  -b ${SNORT_TAG} --depth 1 https://github.com/snort3/snort3.git

WORKDIR $BUILD_DIR/snort3
RUN ./configure_cmake.sh \
    --prefix=${PREFIX_DIR} \
    --enable-unit-tests \
    --disable-docs


WORKDIR $BUILD_DIR/snort3/build
RUN make VERBOSE=1 && \
    make install

#
# RUNTIME CONTAINER
#
FROM $BASE

ENV PREFIX_DIR=/usr/local/
WORKDIR ${PREFIX_DIR}

# Update APK adding the @testing repo for hwloc (as of Alpine v3.7)
RUN echo '@testing http://nl.alpinelinux.org/alpine/edge/testing' >>/etc/apk/repositories

# Prep APK for installing packages
RUN apk add --no-cache  \
    flatbuffers@testing \
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

