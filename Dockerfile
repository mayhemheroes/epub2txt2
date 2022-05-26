# Build Stage
FROM fuzzers/aflplusplus:3.12c as builder

## Install build dependencies.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y git make unzip

## Add source code to the build stage.
ADD ./epub2txt2
WORKDIR /epub2txt2

## Build
RUN make -j$(nproc) BUILD_FOR_AFL=1

## Prepare all library dependencies for copy
RUN mkdir /deps

## Package Stage
RUN cp `ldd ./src/gregorio-6* | grep so | sed -e '/^[^\t]/ d' | sed -e 's/\t//' | sed -e 's/.*=..//' | sed -e 's/ (0.*)//' | sort | uniq` /deps 2>/dev/null || :

RUN cp corpus/* > /tests/
