# Build Stage
FROM fuzzers/aflplusplus:3.12c as builder

## Install build dependencies.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y git make

## Add source code to the build stage.
WORKDIR /
ADD https://api.github.com/repos/capuanob/epub2txt2/git/refs/heads/mayhem version.json
RUN git clone -b mayhem https://github.com/capuanob/epub2txt2.git
WORKDIR /epub2txt2

## Build
RUN make -j$(nproc) BUILD_FOR_AFL=1 

## Prepare all library dependencies for copy
RUN mkdir /deps

## Prepare all library dependencies for copy
RUN cp `ldd ./epub2txt | grep so | sed -e '/^[^\t]/ d' | sed -e 's/\t//' | sed -e 's/.*=..//' | sed -e 's/ (0.*)//' | sort | uniq` /deps 2>/dev/null || :
RUN cp `ldd /usr/local/bin/afl-fuzz | grep so | sed -e '/^[^\t]/ d' | sed -e 's/\t//' | sed -e 's/.*=..//' | sed -e 's/ (0.*)//' | sort | uniq` /deps 2>/dev/null || :

## Package Stage
FROM --platform=linux/amd64 ubuntu:20.04
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y unzip zip
COPY --from=builder /deps /usr/lib
COPY --from=builder /epub2txt2/epub2txt /epub2txt
COPY --from=builder /usr/local/bin/afl-fuzz /afl-fuzz
COPY --from=builder /epub2txt2/corpus /tests

env AFL_SKIP_CPUFREQ=1
env AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

ENTRYPOINT ["/afl-fuzz", "-i", "/tests", "-o", "/out"]
CMD ["/epub2txt", "@@"]
