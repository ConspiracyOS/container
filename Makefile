PROFILE      ?= minimal
BASE_IMAGE   ?= ubuntu:24.04
IMAGE_NAME   ?= conos
NAME         ?= conos
ARCH         ?= arm64
RUNTIME      ?= docker

# Supply a pre-built conctl binary path, or it will be downloaded from releases.
CONCTL_BIN   ?=
CONCTL_VER   ?= latest

.PHONY: image deploy run stop task status logs responses clean verify-conctl-bin test-conctl-bin-guard test

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

verify-conctl-bin: $(CURDIR)/conctl
	@desc="$$(file $(CURDIR)/conctl)"; \
	echo "$$desc"; \
	echo "$$desc" | grep -q "ELF 64-bit" || { \
		echo "error: conctl binary must be Linux ELF (got host-format binary)"; \
		exit 1; \
	}; \
	case "$(ARCH)" in \
	arm64) echo "$$desc" | grep -q "ARM aarch64" || { \
		echo "error: conctl binary arch mismatch for ARCH=arm64"; \
		exit 1; \
	} ;; \
	amd64) echo "$$desc" | grep -q "x86-64" || { \
		echo "error: conctl binary arch mismatch for ARCH=amd64"; \
		exit 1; \
	} ;; \
	esac

# Build the container image
image: verify-conctl-bin
	$(RUNTIME) build \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	  --build-arg PROFILE=$(PROFILE) \
	  -t $(IMAGE_NAME) \
	  -f $(CURDIR)/Containerfile \
	  $(CURDIR)

# Cheap regression check for guard behavior: text file must fail validation.
test-conctl-bin-guard:
	@tmp=$$(mktemp); \
	backup=$$(mktemp); \
	had_conctl=0; \
	if [ -f "$(CURDIR)/conctl" ]; then cp "$(CURDIR)/conctl" $$backup; had_conctl=1; fi; \
	echo "not a binary" > $$tmp; \
	if CONCTL_BIN=$$tmp $(MAKE) --no-print-directory -B ARCH=$(ARCH) $(CURDIR)/conctl verify-conctl-bin >/tmp/conctl-guard.log 2>&1; then \
		echo "error: expected verify-conctl-bin to fail on invalid binary"; \
		cat /tmp/conctl-guard.log; \
		if [ $$had_conctl -eq 1 ]; then cp $$backup "$(CURDIR)/conctl"; else rm -f "$(CURDIR)/conctl"; fi; \
		rm -f $$backup; \
		rm -f $$tmp; \
		exit 1; \
	fi; \
	if [ $$had_conctl -eq 1 ]; then cp $$backup "$(CURDIR)/conctl"; else rm -f "$(CURDIR)/conctl"; fi; \
	rm -f $$backup; \
	rm -f $$tmp; \
	echo "PASS: verify-conctl-bin rejects invalid binary"

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
	printf '%s' "$(MSG)" | $(RUNTIME) exec -i $(NAME) sh -c "cat > /srv/conos/inbox/$${TASKID}.task && chown a-concierge:agents /srv/conos/inbox/$${TASKID}.task" && \
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

# Run smoke + structural e2e tests inside the container.
# Tests requiring LLM interaction (01-17) are excluded.
test:
	@echo "=== Running smoke tests ==="
	$(RUNTIME) exec $(NAME) bash /test/smoke/smoke_test.sh
	@echo ""
	@echo "=== Running structural e2e tests ==="
	@failed=0; \
	for t in $$($(RUNTIME) exec $(NAME) sh -c 'ls /test/e2e/3[1-9]-*.sh 2>/dev/null'); do \
		echo "--- $$t ---"; \
		$(RUNTIME) exec $(NAME) bash $$t || failed=$$((failed + 1)); \
		echo ""; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "$$failed e2e test suite(s) failed"; \
		exit 1; \
	fi; \
	echo "=== All tests passed ==="

clean:
	rm -f $(CURDIR)/conctl
