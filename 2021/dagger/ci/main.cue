// Starting point: https://docs.dagger.io/1012/ci
package main

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/os"
	"alpha.dagger.io/docker"
)

// dagger input dir source .
source: dagger.#Artifact

// STARTING POINT: ../../../.circleci/config.yml

test_deps: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	copy: "/app": from: source
	env:
		MIX_ENV: "test"
	command: #"""
		echo 'GET ALL TEST DEPENDENCIES'
		mix deps.get
		"""#
	dir: "/app"
}

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
	image:  test_deps
	// QUESTION: WHY DO THE ARTEFACTS KEEP GETTING RE-COMPILED?
	// I can see the /app/_build mounting from cache:
	//
	// #10 Mkdir /cache (cache mount /app/_build)
	// #10 sha256:f6ccd0a871ccdf868048604a7f9bcbddc74c18fc3e7059de6de8ad1ca6ee9452
	// #10 CACHED
	//
	// But even though compilation ran before, and everything compiled OK, it all gets re-compiled 🤔
	cache: "/app/_build": true
	env: {
		// Reference a variable from deps_get so that this #up is linked to that #up
		MIX_ENV: test_deps.env.MIX_ENV
	}
	command: #"""
		echo 'WAIT FOR PostgreSQL'
		echo 'CHECK test'
		ls -lah test
		echo 'RUN TESTS'
		mix test
		"""#
	dir: "/app"
}

// QUESTION: HOW DO I STOP & CLEAN THE test_db CONTAINER?
// There is no container name, so even if I could run docker.#Command, I wouldn't know what container name to use.
