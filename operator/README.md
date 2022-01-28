# SDI Operator

**DO NOT USE** yet!

## Motivation

SDI Observer has been useful so far but prone to errors, hard to maintain, configure, test, install and update. The Operator is built using the well established Operator SDK making it easy to consume, configure and manage.

The Operator is supposed to replace SDI Observer once it reaches the same functionality level.

## Status

**alpha**

Implemented SDI Observer features:
- [x] vsystem route management
- [] slcb route management
- [] configure NFS exports for vsystem-vrep
- [] configre host path mount for diagnostic pods
- [] create cmcertificates secret for image registry
- [] configure node selector on namespace

Missing generic functionality:
- [] SDIObserver status updates

## Usage

Stay tuned!

So far friendly only to developers:

    # make deploy

## Contributing

Requirements:
- Operator SDK 1.15
- go 1.16
- (for testing) OpenShift 4.8 clients and server

Setup:

    git clone github.com/redhat-sap/sap-data-intelligence
    cd sap-data-intelligence/operator
    export GOPATH="$(pwd)/.go"
    export GOCACHE=""
    export GO111MODULE='on'
    export GOFLAGS=-mod=vendor
    go mod init $(pwd)

Test:

    make test

Build and push a new image:

    # # optionally, override DOCKER_CMD to e.g. docker
    make docker-build docker-push
