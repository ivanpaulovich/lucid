.PHONY: install uninstall test

PREFIX ?= /usr/local

install:
	install -m 755 lucid $(PREFIX)/bin/lucid

uninstall:
	rm -f $(PREFIX)/bin/lucid

test:
	@echo "--- stdin check ---"
	@echo "" | ./lucid 2>&1 | grep -q "empty diff" && echo "PASS: empty diff"
	@./lucid --version | grep -q "lucid" && echo "PASS: --version"
	@echo "All tests passed."
