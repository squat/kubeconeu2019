export GO111MODULE=on
.PHONY: all push container clean container-name container-latest push-latest local fmt lint test

ARCH ?= amd64
ALL_ARCH := amd64 arm arm64
DOCKER_ARCH := "amd64" "arm v7" "arm64 v8"
BIN := kceu
PROJECT := kubeconeu2019
PKG := github.com/squat/$(PROJECT)
REGISTRY ?= index.docker.io
IMAGE ?= squat/$(PROJECT)

CAM2IP_PKG := github.com/gen2brain/cam2ip/cmd/cam2ip
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

BUILD_IMAGE ?= golang:1.13.0-alpine

build: bin/$(ARCH)/$(BIN)

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

fmt:
	@echo $(GO_PKGS)
	gofmt -w -s $(SRC)

lint:
	@echo 'golint $(GO_PKGS)'
	@lint_res=$$(golint $(GO_PKGS)); if [ -n "$$lint_res" ]; then \
		echo ""; \
		echo "Golint found style issues. Please check the reported issues"; \
		echo "and fix them if necessary before submitting the code for review:"; \
		echo "$$lint_res"; \
		exit 1; \
	fi
	@echo 'gofmt -d -s $(SRC)'
	@fmt_res=$$(gofmt -d -s $(SRC)); if [ -n "$$fmt_res" ]; then \
		echo ""; \
		echo "Gofmt found style issues. Please check the reported issues"; \
		echo "and fix them if necessary before submitting the code for review:"; \
		echo "$$fmt_res"; \
		exit 1; \
	fi

test: lint vet

container: .container-$(ARCH)-$(VERSION) container-name
.container-$(ARCH)-$(VERSION): bin/$(ARCH)/$(BIN) Dockerfile
	@i=0; for a in $(ALL_ARCH); do [ "$$a" = $(ARCH) ] && break; i=$$((i+1)); done; \
	ia=""; iv=""; \
	j=0; for a in $(DOCKER_ARCH); do \
	    [ "$$i" -eq "$$j" ] && ia=$$(echo "$$a" | awk '{print $$1}') && iv=$$(echo "$$a" | awk '{print $$2}') && break; j=$$((j+1)); \
	done; \
	SHA=$$(docker manifest inspect $(BUILD_IMAGE) | jq '.manifests[] | select(.platform.architecture == "'$$ia'") | if .platform | has("variant") then select(.platform.variant == "'$$iv'") else . end | .digest' -r); \
	docker build -t $(IMAGE):$(ARCH)-$(VERSION) --build-arg FROM=$(BUILD_IMAGE)@$$SHA --build-arg GOARCH=$(ARCH) .
	@docker images -q $(IMAGE):$(ARCH)-$(VERSION) > $@

container-latest: .container-$(ARCH)-$(VERSION)
	@docker tag $(IMAGE):$(ARCH)-$(VERSION) $(IMAGE):$(ARCH)-latest
	@echo "container: $(IMAGE):$(ARCH)-latest"

container-name:
	@echo "container: $(IMAGE):$(ARCH)-$(VERSION)"

manifest: .manifest-$(VERSION) manifest-name
.manifest-$(VERSION): Dockerfile $(addprefix push-, $(ALL_ARCH))
	@docker manifest create --amend $(IMAGE):$(VERSION) $(addsuffix -$(VERSION), $(addprefix squat/$(PROJECT):, $(ALL_ARCH)))
	@$(MAKE) --no-print-directory manifest-annotate-$(VERSION)
	@docker manifest push $(IMAGE):$(VERSION) > $@

manifest-latest: Dockerfile $(addprefix push-latest-, $(ALL_ARCH))
	@docker manifest create --amend $(IMAGE):latest $(addsuffix -latest, $(addprefix squat/$(PROJECT):, $(ALL_ARCH)))
	@$(MAKE) --no-print-directory manifest-annotate-latest
	@docker manifest push $(IMAGE):latest
	@echo "manifest: $(IMAGE):latest"

manifest-annotate: manifest-annotate-$(VERSION)

manifest-annotate-%:
	@i=0; \
	for a in $(ALL_ARCH); do \
	    annotate=; \
	    j=0; for da in $(DOCKER_ARCH); do \
		if [ "$$j" -eq "$$i" ] && [ -n "$$da" ]; then \
		    annotate="docker manifest annotate $(IMAGE):$* $(IMAGE):$$a-$* --os linux --arch"; \
		    k=0; for ea in $$da; do \
			[ "$$k" = 0 ] && annotate="$$annotate $$ea"; \
			[ "$$k" != 0 ] && annotate="$$annotate --variant $$ea"; \
			k=$$((k+1)); \
		    done; \
		    $$annotate; \
		fi; \
		j=$$((j+1)); \
	    done; \
	    i=$$((i+1)); \
	done

manifest-name:
	@echo "manifest: $(IMAGE_ROOT):$(VERSION)"

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
