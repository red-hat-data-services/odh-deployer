CONTAINER_REPO := quay.io/modh
CONTAINER_IMAGE := odh-deployer

VERSION := $(shell git describe --match 'v[0-9]*' --tags --abbrev=0 2> /dev/null)
RELEASE := $(shell git rev-parse --short HEAD)

.PHONY: all
all: build-img push-img

.PHONY: build-img
build-img:
	podman build \
	  --build-arg "CI_CONTAINER_VERSION=$(VERSION)" \
	  --build-arg "CI_CONTAINER_RELEASE=$(RELEASE)" \
	  -t $(CONTAINER_REPO)/$(CONTAINER_IMAGE):$(VERSION)-$(RELEASE) \
	  -f Dockerfile .

.PHONY: push-img
push-img:
	podman push $(CONTAINER_REPO)/$(CONTAINER_IMAGE):$(VERSION)-$(RELEASE)
