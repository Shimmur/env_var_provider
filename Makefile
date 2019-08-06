.PHONY: help

APP_NAME ?= `pwd | xargs basename | tr '[A-Z]' '[a-z]'`
APP_VSN ?= `grep 'version:' mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`

help:
	@echo "$(APP_NAME):$(APP_VSN)-$(BUILD)"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build:
	docker build --build-arg APP_NAME=$(APP_NAME) \
	--build-arg APP_VSN=$(APP_VSN) \
	--build-arg HEXPM_KEY=$(HEXPM_KEY) \
	-t $(APP_NAME):$(APP_VSN)-$(BUILD) \
	-t $(APP_NAME):latest . \
	-t quay.io/shimmur/$(APP_NAME):$(APP_VSN)-$(BUILD)

run:
	docker run -it --env-file .docker-env $(APP_NAME):latest 

push:
	docker push quay.io/shimmur/$(APP_NAME):$(APP_VSN)-$(BUILD)

code-check:
	mix format --check-formatted
	mix compile --force --warnings-as-errors
	mix lint.credo
