PROFILE      ?= minimal
BASE_IMAGE   ?= ubuntu:24.04
IMAGE_NAME   ?= conos
NAME         ?= conos
ARCH         ?= arm64
RUNTIME      ?= docker

# Supply a pre-built conctl binary path, or it will be downloaded from releases.
CONCTL_BIN   ?=
CONCTL_VER   ?= latest

.PHONY: image deploy run stop task status logs responses clean

# Acquire conctl binary: copy from CONCTL_BIN or download from releases.
$(CURDIR)/conctl:
ifeq ($(CONCTL_BIN),)
	curl -fsSL \
	  https://github.com/ConspiracyOS/conctl/releases/$(CONCTL_VER)/download/conctl-linux-$(ARCH) \
	  -o $(CURDIR)/conctl
	chmod +x $(CURDIR)/conctl
else
	cp $(CONCTL_BIN) $(CURDIR)/conctl
	chmod +x $(CURDIR)/conctl
endif

# Build the container image
image: $(CURDIR)/conctl
	$(RUNTIME) build \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	  --build-arg PROFILE=$(PROFILE) \
	  -t $(IMAGE_NAME) \
	  -f $(CURDIR)/Containerfile \
	  $(CURDIR)

# Start the container (detached)
run:
	$(RUNTIME) run -d --name $(NAME) --env-file srv/dev/container.env $(IMAGE_NAME)

# Stop and remove the container
stop:
	$(RUNTIME) stop $(NAME) && $(RUNTIME) rm $(NAME)

# Rebuild image and restart container
deploy: image
	-$(RUNTIME) kill $(NAME) 2>/dev/null; $(RUNTIME) rm $(NAME) 2>/dev/null
	$(RUNTIME) run -d --name $(NAME) --env-file srv/dev/container.env $(IMAGE_NAME)

# Drop a task into the outer inbox
# Usage: make task MSG="your message here"
task:
	@if [ -z "$(MSG)" ]; then echo "Usage: make task MSG=\"your message\""; exit 1; fi
	@TASKID=$$(date +%s); \
	$(RUNTIME) exec $(NAME) sh -c "printf '%s' '$(MSG)' > /srv/conos/inbox/$${TASKID}.task && chown a-concierge:agents /srv/conos/inbox/$${TASKID}.task" && \
	echo "Task $${TASKID}.task dropped into inbox"

# Show agent status
status:
	$(RUNTIME) exec $(NAME) conctl status

# Tail the audit log
logs:
	$(RUNTIME) exec $(NAME) conctl logs

# Show latest responses from each agent outbox
responses:
	$(RUNTIME) exec $(NAME) conctl responses

clean:
	rm -f $(CURDIR)/conctl
