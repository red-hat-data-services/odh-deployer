CONTAINER_REPO := quay.io/opendatahub
CONTAINER_IMAGE := odh-deployer

BUILDDATE := $(shell date -u '+%Y-%m-%dT%H:%M:%S.%NZ')
VERSION := v0.8.0
VCS := $(shell git describe --match 'v[0-9]*' --tags --dirty 2> /dev/null || git describe --always --dirty)

.PHONY: all
all: build

.PHONY: build
build:
	podman build \
	  --build-arg "builddate=$(BUILDDATE)" \
	  --build-arg "version=$(VERSION)" \
	  --build-arg "vcs=$(VCS)" \
	  -t $(CONTAINER_REPO)/$(CONTAINER_IMAGE):$(VERSION) \
	  -f Dockerfile .

push:
	podman push $(CONTAINER_REPO)/$(CONTAINER_IMAGE):$(VERSION)
