// Starting point: https://docs.dagger.io/1012/ci
package main

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/os"
	"alpha.dagger.io/docker"
)

// dagger input dir source .
source: dagger.#Artifact

// Starting point: .circleci/config.yml
deps_get: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	copy: "/app": from: source
	env:
		MIX_ENV: "test"
	command: "mix deps.get"
	dir:     "/app"
}

deps_compile: os.#Container & {
	image: deps_get
	cache: "/app/_build": true
	env: {
		// Reference a variable from deps_get so that this #up is linked to that #up
		MIX_ENV: deps_get.env.MIX_ENV
	}
	command: #"""
		find deps
		mix deps.compile
		"""#
	dir: "/app"
}

// Start PostgreSQL Docker container:
// https://github.com/thechangelog/changelog.com/blob/fb661d0cf3a4db731d46ef7f1cec44a5d1f4581a/.circleci/config.yml#L55-L59

// Wait for PostgreSQL to start, then run tests:
// https://github.com/thechangelog/changelog.com/blob/fb661d0cf3a4db731d46ef7f1cec44a5d1f4581a/.circleci/config.yml#L66-L76
