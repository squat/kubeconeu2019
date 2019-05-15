export GO111MODULE=on
.PHONY: all push container clean container-name container-latest push-latest local fmt lint test

ARCH ?= amd64
ALL_ARCH := amd64 arm arm64
BIN := kceu
PROJECT := kubeconeu2019
PKG := github.com/squat/$(PROJECT)
REGISTRY ?= index.docker.io
IMAGE ?= squat/$(PROJECT)

STREAMER_PKG := github.com/blackjack/webcam/examples/http_mjpeg_streamer
TAG := $(shell git describe --abbrev=0 --tags HEAD 2>/dev/null)
COMMIT := $(shell git rev-parse HEAD)
VERSION := $(COMMIT)
ifneq ($(TAG),)
    ifeq ($(COMMIT), $(shell git rev-list -n1 $(TAG)))
        VERSION := $(TAG)
    endif
endif
DIRTY := $(shell test -z "$$(git diff --shortstat 2>/dev/null)" || echo -dirty)
VERSION := $(VERSION)$(DIRTY)
SRC := $(shell find . -type f -name '*.go' -not -path "./vendor/*")

BUILD_IMAGE ?= golang:1.12.1-alpine

build: bin/$(ARCH)/$(BIN) bin/$(ARCH)/mjpeg

build-%:
	@$(MAKE) --no-print-directory ARCH=$* build

container-latest-%:
	@$(MAKE) --no-print-directory ARCH=$* container-latest

container-%:
	@$(MAKE) --no-print-directory ARCH=$* container

push-latest-%:
	@$(MAKE) --no-print-directory ARCH=$* push-latest

push-%:
	@$(MAKE) --no-print-directory ARCH=$* push

all-build: $(addprefix build-, $(ALL_ARCH))

all-container: $(addprefix container-, $(ALL_ARCH))

all-push: $(addprefix push-, $(ALL_ARCH))

all-container-latest: $(addprefix container-latest-, $(ALL_ARCH))

all-push-latest: $(addprefix push-latest-, $(ALL_ARCH))

bin/$(ARCH):
	@mkdir -p $@

bin/$(ARCH)/$(BIN): $(SRC) go.mod bin/$(ARCH)
	@docker run --rm \
	    -u $$(id -u):$$(id -g) \
    	    -v $$(pwd):/$(PROJECT) \
	    -v $$(pwd)/.go/std/$(ARCH):/usr/local/go/pkg/linux_$(ARCH)_static \
	    -w /$(PROJECT) \
	    $(BUILD_IMAGE) \
	    /bin/sh -c " \
		GOARCH=$(ARCH) \
		GOOS=linux \
	        GOCACHE=/$(PROJECT)/.cache \
		CGO_ENABLED=0 \
		go build -mod=vendor -o $@ \
	    "

bin/$(ARCH)/mjpeg: bin/$(ARCH)
	@docker run --rm \
	    -u $$(id -u):$$(id -g) \
    	    -v $$(pwd):/$(PROJECT) \
	    -v $$(pwd)/.go/std/$(ARCH):/usr/local/go/pkg/linux_$(ARCH)_static \
	    -w /$(PROJECT) \
	    $(BUILD_IMAGE) \
	    /bin/sh -c " \
		GOOS=linux \
	        GOCACHE=/$(PROJECT)/.cache \
		CGO_ENABLED=0 \
		go build -mod=vendor -o $@ \
		    $(STREAMER_PKG) \
	    "


fmt:
	@echo $(GO_PKGS)
	gofmt -w -s $(GO_FILES)

lint:
	@echo 'golint $(GO_PKGS)'
	@lint_res=$$(golint $(GO_PKGS)); if [ -n "$$lint_res" ]; then \
		echo ""; \
		echo "Golint found style issues. Please check the reported issues"; \
		echo "and fix them if necessary before submitting the code for review:"; \
		echo "$$lint_res"; \
		exit 1; \
	fi
	@echo 'gofmt -d -s $(GO_FILES)'
	@fmt_res=$$(gofmt -d -s $(GO_FILES)); if [ -n "$$fmt_res" ]; then \
		echo ""; \
		echo "Gofmt found style issues. Please check the reported issues"; \
		echo "and fix them if necessary before submitting the code for review:"; \
		echo "$$fmt_res"; \
		exit 1; \
	fi
	@echo 'yarn --cwd static run lint'
	@if ! tslint_res=$$(yarn --cwd static run lint); then \
		echo ""; \
		echo "tslint found style issues. Please check the reported issues"; \
		echo "and fix them if necessary before submitting the code for review:"; \
		echo "$$tslint_res"; \
		exit 1; \
	fi

test: lint vet

container: .container-$(ARCH)-$(VERSION) container-name
.container-$(ARCH)-$(VERSION): bin/$(ARCH)/$(BIN) Dockerfile bin/$(ARCH)/mjpeg
	@docker build -t $(IMAGE):$(ARCH)-$(VERSION) --build-arg ARCH=$(ARCH) .
	@docker images -q $(IMAGE):$(ARCH)-$(VERSION) > $@

container-latest: .container-$(ARCH)-$(VERSION)
	@docker tag $(IMAGE):$(ARCH)-$(VERSION) $(IMAGE):$(ARCH)-latest
	@echo "container: $(IMAGE):$(ARCH)-latest"

container-name:
	@echo "container: $(IMAGE):$(ARCH)-$(VERSION)"

push: .push-$(ARCH)-$(VERSION) push-name
.push-$(ARCH)-$(VERSION): .container-$(ARCH)-$(VERSION)
	@docker push $(REGISTRY)/$(IMAGE):$(ARCH)-$(VERSION)
	@docker images -q $(IMAGE):$(ARCH)-$(VERSION) > $@

push-latest: container-latest
	@docker push $(REGISTRY)/$(IMAGE):$(ARCH)-latest
	@echo "pushed: $(IMAGE):$(ARCH)-latest"

push-name:
	@echo "pushed: $(IMAGE):$(ARCH)-$(VERSION)"

clean: container-clean bin-clean

container-clean:
	rm -rf .container-* .push-*

bin-clean:
	rm -rf bin

vet:
	@echo 'go vet $(GO_PKGS)'
	@go vet $(GO_PKGS); if [ $$? -eq 1 ]; then \
		echo ""; \
		echo "Vet found suspicious constructs. Please check the reported constructs"; \
		echo "and fix them if necessary before submitting the code for review."; \
		exit 1; \
	fi