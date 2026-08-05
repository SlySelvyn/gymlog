# GymLog — containerized build/test environment for the CoreLogic package.
#
# The iOS app target (iOSApp/) requires Xcode on macOS and cannot run in a
# container. This image packages everything that CAN run anywhere: the Swift
# toolchain plus the platform-independent GymLogCore package and its full
# test suite, so any work environment with Docker can build and test the core
# without installing Swift locally.
#
# Build:  docker build -t gymlog-core .
# Test:   docker run --rm gymlog-core            (runs `swift test`)
# Shell:  docker run --rm -it gymlog-core bash

FROM swift:5.10-jammy

WORKDIR /app/CoreLogic

# Manifest first so dependency resolution caches independently of source edits.
COPY CoreLogic/Package.swift ./
RUN swift package resolve

COPY CoreLogic/Sources ./Sources
COPY CoreLogic/Tests ./Tests

# Pre-build so the image ships with compiled artifacts; `docker run` then only
# builds the test bundle.
RUN swift build

CMD ["swift", "test"]
