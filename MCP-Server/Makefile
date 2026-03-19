PID_FILE  = .server.pid
PORT      = 8080
PRODUCT   = MCPGitHTTP
DEBUG_BIN = .build/debug/$(PRODUCT)
REL_BIN   = .build/release/$(PRODUCT)

.PHONY: build build-release run run-release start stop restart status logs clean test test-client help

# ── Compile ────────────────────────────────────────────────

## Compile debug binary (fast, incremental)
build:
	swift build --product $(PRODUCT)

## Compile optimised release binary
build-release:
	swift build -c release --product $(PRODUCT)

# ── Run (no recompile) ─────────────────────────────────────

## Run the existing debug binary — does NOT recompile.
## Build first with: make build
run:
	@test -f $(DEBUG_BIN) || (echo "❌  Binary not found. Run 'make build' first." && exit 1)
	$(DEBUG_BIN)

## Run the existing release binary — does NOT recompile.
## Build first with: make build-release
run-release:
	@test -f $(REL_BIN) || (echo "❌  Binary not found. Run 'make build-release' first." && exit 1)
	$(REL_BIN)

# ── Background management ──────────────────────────────────

## Build release and start in the background
start: build-release
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		echo "⚠️  Уже запущен (PID $$(cat $(PID_FILE)))"; \
	else \
		$(REL_BIN) > .server.log 2>&1 & \
		echo $$! > $(PID_FILE); \
		sleep 1; \
		if kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
			echo "🚀 Запущен (PID $$(cat $(PID_FILE)), порт $(PORT))"; \
		else \
			echo "❌ Не удалось запустить"; rm -f $(PID_FILE); \
		fi \
	fi

stop:
	@if [ -f $(PID_FILE) ]; then \
		kill $$(cat $(PID_FILE)) 2>/dev/null && \
			echo "🛑 Остановлен (PID $$(cat $(PID_FILE)))" || \
			echo "⚠️  Процесс уже не существует"; \
		rm -f $(PID_FILE); \
	else \
		PID=$$(lsof -ti :$(PORT)); \
		if [ -n "$$PID" ]; then \
			kill $$PID && echo "🛑 Убит процесс $$PID"; \
		else \
			echo "✅ Ничего не запущено"; \
		fi \
	fi

restart: stop start

status:
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		echo "✅ Работает (PID $$(cat $(PID_FILE)))"; \
		curl -s http://localhost:$(PORT)/health | python3 -m json.tool 2>/dev/null || true; \
	else \
		echo "⭕ Не запущен"; rm -f $(PID_FILE) 2>/dev/null; \
	fi

logs:
	@tail -f .server.log 2>/dev/null || echo "Нет лог-файла"

# ── Testing ────────────────────────────────────────────────

## Test via MCP Streamable HTTP (requires running server).
## The server creates a session on the first POST with initialize.
test:
	@echo "=== MCP Streamable HTTP — initialize ==="
	@SESSION=$$(curl -s -D - -X POST http://localhost:$(PORT)/mcp \
		-H "Content-Type: application/json" \
		-H "Accept: application/json, text/event-stream" \
		-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
		2>/dev/null | grep -i "mcp-session-id" | awk '{print $$2}' | tr -d '\r'); \
	echo "Session: $$SESSION"

test-client: build
	$(DEBUG_BIN) &
	sleep 2
	.build/debug/MCPGitClient http://localhost:$(PORT)/mcp || true

# ── Cleanup ────────────────────────────────────────────────

clean: stop
	rm -rf .build .server.log .server.pid

# ── Help ──────────────────────────────────────────────────

help:
	@echo ""
	@echo "  make build          — скомпилировать debug-бинарь (инкрементально)"
	@echo "  make build-release  — скомпилировать оптимизированный release"
	@echo "  make run            — запустить debug-бинарь БЕЗ перекомпиляции"
	@echo "  make run-release    — запустить release-бинарь БЕЗ перекомпиляции"
	@echo "  make start          — release в фоне (build + start)"
	@echo "  make stop           — остановить фоновый сервер"
	@echo "  make restart        — перезапустить"
	@echo "  make status         — статус + health"
	@echo "  make logs           — tail логов фонового сервера"
	@echo "  make test           — тест MCP initialize через curl"
	@echo "  make test-client    — полный тест через SDK клиент"
	@echo "  make clean          — удалить .build и логи"
	@echo ""
