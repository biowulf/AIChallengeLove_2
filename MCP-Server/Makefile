PID_FILE = .server.pid
PORT = 8080

.PHONY: build run stop restart status logs clean test test-repos test-issues test-client help

build:
	swift build -c release

run: build
	.build/release/MCPGitHTTP

start: build
	@if [ -f $(PID_FILE) ] && kill -0 $$(cat $(PID_FILE)) 2>/dev/null; then \
		echo "⚠️  Уже запущен (PID $$(cat $(PID_FILE)))"; \
	else \
		.build/release/MCPGitHTTP > .server.log 2>&1 & \
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

test:
	@curl -s -X POST http://localhost:$(PORT)/mcp \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m json.tool

test-repos:
	@curl -s -X POST http://localhost:$(PORT)/mcp \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_repos","arguments":{"language":"Swift"}}}' | python3 -m json.tool

test-issues:
	@curl -s -X POST http://localhost:$(PORT)/mcp \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_issues","arguments":{"repo":"ios-weather-app","state":"open"}}}' | python3 -m json.tool

test-client: build
	.build/release/MCPGitClient http://localhost:$(PORT)/mcp

clean: stop
	rm -rf .build .server.log .server.pid

help:
	@echo ""
	@echo "  make build       — собрать"
	@echo "  make run         — Vapor на переднем плане (Ctrl+C)"
	@echo "  make start       — Vapor в фоне"
	@echo "  make stop        — остановить"
	@echo "  make restart     — перезапустить"
	@echo "  make status      — статус + health"
	@echo "  make test        — tools/list"
	@echo "  make test-repos  — list_repos"
	@echo "  make test-issues — get_issues"
	@echo "  make test-client — полный демо через SDK клиент"
	@echo "  make clean       — очистить всё"
	@echo ""
