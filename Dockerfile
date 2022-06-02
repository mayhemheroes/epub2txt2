# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder

## Install build dependencies.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y git make clang

## Add source code to the build stage.
WORKDIR /
ADD https://api.github.com/repos/capuanob/epub2txt2/git/refs/heads/mayhem version.json
RUN git clone -b mayhem https://github.com/capuanob/epub2txt2.git
WORKDIR /epub2txt2

## Build
RUN make -j$(nproc)

## Prepare all library dependencies for copy
RUN mkdir /deps

## Package Stage
RUN cp `ldd ./src/gregorio-6* | grep so | sed -e '/^[^\t]/ d' | sed -e 's/\t//' | sed -e 's/.*=..//' | sed -e 's/ (0.*)//' | sort | uniq` /deps 2>/dev/null || :

## Generate test corpus
RUN cp corpus/* > /tests/

ENTRYPOINT ["afl-fuzz", "-i", "/tests", "-o", "/out"]
CMD ["/epub2txt2/epub2txt", "@@"]
