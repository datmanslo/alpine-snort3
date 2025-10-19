#
# BUILD CONTAINER
# (Note that this is a multi-phase Dockerfile)
# To build run `docker build --rm -t snort3-alpine:latest`
# By default the latest code will be pulled from the Snort, libdaq, and libml master branches
# To build specific tagged releases add the appropriate --build args e.g.:
#  `docker build --build-arg BASE=alpine:3.11 --build-arg SNORT_TAG=3.0.0-268 --build-arg DAQ_TAG=v3.0.0-alpha3 --build-arg LIBML_TAG=v1.0.0 -t snort3-alpine:3.0.0-268`
#

ARG BASE=alpine:3.22

FROM $BASE as builder

ARG SNORT_TAG=master
ARG DAQ_TAG=master
ARG LIBML_TAG=master

ENV PREFIX_DIR=/usr/local
ENV BUILD_DIR=/tmp

# Install buildtime packages
RUN apk add --no-cache \
    autoconf \
    automake \
    linux-headers \
    wget \
    build-base \
    git \
    cmake \
    bison \
    flex \
    flex-dev \
    cppcheck \
    cpputest \
    flatbuffers-dev \
    hwloc-dev \
    libdnet-dev \
    libpcap-dev \
    libtirpc-dev \
    libmnl-dev \
    luajit-dev \
    openssl-dev \
    libtool \
    libnetfilter_queue-dev \
    zlib-dev \
    pcre2-dev \
    libuuid \
    xz-dev \
    vectorscan-dev \
    jemalloc-dev

# BUILD Daq

WORKDIR $BUILD_DIR
RUN git clone -b ${DAQ_TAG} --depth 1 https://github.com/snort3/libdaq.git

WORKDIR $BUILD_DIR/libdaq
RUN ./bootstrap && \
    ./configure --prefix=${PREFIX_DIR} && \
    make -j$(nproc) install

# BUILD libml
WORKDIR $BUILD_DIR
RUN git clone -b ${LIBML_TAG} --depth 1 https://github.com/snort3/libml.git

WORKDIR $BUILD_DIR/libml
# Patch vendored flatbuffers for musl libc compatibility
RUN sed -i 's/#define __strtoll_impl(s, pe, b) strtoll_l(s, pe, b, ClassicLocale::Get())/#define __strtoll_impl(s, pe, b) strtoll(s, pe, b)/' vendor/flatbuffers/include/flatbuffers/util.h && \
    sed -i 's/#define __strtoull_impl(s, pe, b) strtoull_l(s, pe, b, ClassicLocale::Get())/#define __strtoull_impl(s, pe, b) strtoull(s, pe, b)/' vendor/flatbuffers/include/flatbuffers/util.h && \
    sed -i 's/#define __strtod_impl(s, pe) strtod_l(s, pe, ClassicLocale::Get())/#define __strtod_impl(s, pe) strtod(s, pe)/' vendor/flatbuffers/include/flatbuffers/util.h && \
    sed -i 's/#define __strtof_impl(s, pe) strtof_l(s, pe, ClassicLocale::Get())/#define __strtof_impl(s, pe) strtof(s, pe)/' vendor/flatbuffers/include/flatbuffers/util.h
RUN ./configure.sh && \
    cd build && \
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
   --enable-large-pcap \
   --enable-jemalloc

WORKDIR $BUILD_DIR/snort3/build
RUN make VERBOSE=1 -j$(nproc) install

#
# RUNTIME CONTAINER
#
FROM $BASE

ENV PREFIX_DIR=/usr/local
WORKDIR ${PREFIX_DIR}

# Install runtime packages
RUN apk add --no-cache \
    flatbuffers \
    hwloc \
    libdnet \
    luajit \
    openssl \
    libpcap \
    libmnl \
    libnetfilter_queue \
    pcre2 \
    libtirpc \
    musl \
    libstdc++ \
    libuuid \
    zlib \
    xz \
    vectorscan \
    jemalloc

# Copy the build artifacts from the build container to the runtime file system
COPY --from=builder ${PREFIX_DIR}/etc/ ${PREFIX_DIR}/etc/
COPY --from=builder ${PREFIX_DIR}/lib/ ${PREFIX_DIR}/lib/
COPY --from=builder ${PREFIX_DIR}/bin/ ${PREFIX_DIR}/bin/

WORKDIR /
RUN snort --version

