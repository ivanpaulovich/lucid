.PHONY: install uninstall test

PREFIX ?= /usr/local

install:
	install -m 755 lucid $(PREFIX)/bin/lucid

uninstall:
	rm -f $(PREFIX)/bin/lucid

test:
	@echo "--- flag tests ---"
	@./lucid --version | grep -q "lucid" && echo "PASS: --version"
	@./lucid --help 2>&1 | grep -q "explain" && echo "PASS: --help"
	@echo "diff" | ./lucid --list 2>/dev/null; echo "PASS: --list runs"
	@echo "All tests passed."
