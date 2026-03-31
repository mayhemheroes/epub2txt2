# Build Stage
FROM fuzzers/aflplusplus:3.12c as builder

## Install build dependencies.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y make

## Add source code to the build stage.
ADD . /epub2txt2
WORKDIR /epub2txt2

## Build
RUN make -j$(nproc) BUILD_FOR_AFL=1

## Package Stage
FROM fuzzers/aflplusplus:3.12c
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y unzip zip
COPY --from=builder /epub2txt2/epub2txt /epub2txt
COPY --from=builder /epub2txt2/corpus /tests

ENTRYPOINT ["afl-fuzz", "-i", "/tests", "-o", "/out"]
CMD ["/epub2txt", "@@"]
