.PHONY: up down migrate migrate-down migrate-status test build lint

up:
	docker compose up -d --wait postgres adminer

down:
	docker compose down

migrate:
	docker compose run --rm migrate

migrate-down:
	docker compose run --rm -e GOOSE_COMMAND=down migrate

migrate-status:
	docker compose run --rm -e GOOSE_COMMAND=status migrate

test:
	go test ./...

build: 
	go build ./...

lint:
	@echo "not implemented yet"
