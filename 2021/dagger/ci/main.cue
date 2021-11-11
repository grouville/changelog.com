// Starting point: https://docs.dagger.io/1012/ci
package main

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/os"
	"alpha.dagger.io/docker"
)

source: dagger.#Artifact

// Starting point: .circleci/config.yml
deps_get: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	mount: {
		"/app": from: source
	}
	cache: {
		"/app/deps": true
	}
	command: """
		  mix deps.get
		"""
	env:
		MIX_ENV: "test"
	dir: "/app"
}

// How do I run this AFTER deps_get?
// I will need to share the /apps/deps volume from deps_get
deps_compile: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	mount: {
		"/app": from: source
	}
	cache: {
		"/app/deps":   true
		"/app/_build": true
	}
	command: """
		  mix deps.compile
		"""
	env:
		MIX_ENV: "test"
	dir: "/app"
}

// 🤔 How do we spin another container for PostgreSQL, and tear it down when done?

// prod: os.#Container & {
//  image: docker.#Pull & {
//   from: "thechangelog/runtime:2021-05-29T10.17.12Z"
//  }
//  mount: "/app": from: source
//  command: """
//     mix do deps.get, deps.compile
//     cd assets && yarn install --frozen-lockfile
//   """
//  env:
//   MIX_ENV: "prod"
//  dir: "/app"
// }
