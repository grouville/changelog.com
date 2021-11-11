// Starting point: https://docs.dagger.io/1012/ci
// 💡 Formatting differs because https://github.com/jjo/vim-cue auto formats - go fmt FTW!
package main

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/os"
	"alpha.dagger.io/docker"
)

source: dagger.#Artifact

// 🤔 How do we split this in multiple steps, with caching for deps & compilation?
// 🤔 How do we spin another container for PostgreSQL, and tear it down when done?
// Starting point: .circleci/config.yml
test: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	mount: "/app": from: source
	cache: {
		"/app/_build": true
		"/app/deps":   true
	}
	command: """
		  mix do deps.get, deps.compile, test
		"""
	env:
		MIX_ENV: "test"
	dir: "/app"
}

prod: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	mount: "/app": from: source
	command: """
		  mix do deps.get, deps.compile
		  cd assets && yarn install --frozen-lockfile
		"""
	env:
		MIX_ENV: "prod"
	dir: "/app"
}
