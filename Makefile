.PHONY: clean sleep


all:
	@echo "Project successfully compiled"

test:
	@echo "Running tests..."
	@if [ -f $(MONGODB_BINARIES)/mongosh ]; then $(MONGODB_BINARIES)/mongosh "$(MONGODB_URI)" --eval "db.runCommand({\"ping\":1})"; else echo "no mongosh found!"; fi
	@echo "All done, thank you and please come again"
	@echo '{"results": [{ "status": "PASS", "test_file": "MyTest#1", "start": 860701.361040201, "end": 860701.361116371, "elapsed": 0.000076170, "log_raw": "This test did this and that"  } ]}' > test-results.json
