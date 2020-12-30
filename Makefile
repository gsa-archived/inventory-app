.PHONY: all build requirements setup test update-dependencies

all: up

build:
	docker-compose build

clean:
	docker-compose down -v --remove-orphans

debug:
	docker-compose kill app ; docker-compose -f docker-compose.debug.yml -f docker-compose.yml run --service-ports app

requirements:
	docker-compose run --rm -T app pip --quiet freeze > requirements-freeze.txt

restart:
	docker-compose exec app pkill -f gunicorn ; docker-compose up -d -- app

test:
	docker-compose -f docker-compose.yml -f docker-compose.test.yml -f docker-compose.seed.yml build
	docker-compose -f docker-compose.yml -f docker-compose.test.yml -f docker-compose.seed.yml build --build-arg REQUIREMENTS_FILE app
	docker-compose -f docker-compose.yml -f docker-compose.test.yml -f docker-compose.seed.yml up --abort-on-container-exit test

up:
	docker-compose up -d

up-with-data:
	docker-compose -f docker-compose.yml -f docker-compose.seed.yml build
	docker-compose -f docker-compose.yml -f docker-compose.seed.yml up

update-dependencies:
	docker-compose run --rm app pip install -r requirements.txt
