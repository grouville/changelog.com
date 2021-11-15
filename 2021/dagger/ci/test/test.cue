// STARTING POINT: https://www.youtube.com/watch?v=QvyB3m9Fti0
// + ../../../.circleci/config.yml
package ci

import (
	"alpha.dagger.io/os"
	"alpha.dagger.io/docker"
)

app_env: "test"

test_db: os.#Container & {
	always: true
	image:  docker.#Pull & {
		from: "circleci/postgres:12.6"
	}
	command: #"""
		echo 'START PostgreSQL - REQUIRED BY INTEGRATION TESTS'
		docker-entrypoint.sh postgres
		"""#
	env: {
		POSTGRES_USER:     "postgres"
		POSTGRES_DB:       "changelog_test"
		POSTGRES_PASSWORD: "postgres"
	}
}

test: os.#Container & {
	always: true
	image:  deps_compile
	env: {
		MIX_ENV: app_env
	}
	command: #"""
		echo 'RUN TESTS'
		mix test
		"""#
	dir: "/app"
}

// QUESTION: HOW DO I STOP & CLEAN THE test_db CONTAINER?
// There is no container name, so even if I could run docker.#Command, I wouldn't know what container name to use.
