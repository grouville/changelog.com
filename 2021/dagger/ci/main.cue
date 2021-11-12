// Starting point: https://docs.dagger.io/1012/ci
package main

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/os"
	"alpha.dagger.io/docker"
)

// dagger input dir source .
source: dagger.#Artifact

// [ for env in 

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
	env:
		MIX_ENV: "test"
	command: "mix deps.get"
	// Directory in which the command is executed
	dir: "/app"
}

deps_compile: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	copy: "/app": from: os.#Dir & {
		from: deps_get
		path: "/app"
	}
	cache: {
		"/app/_build": true
	}
	env: {
		// Reference a variable from deps_get so that this #up is linked to that #up
		MIX_ENV: deps_get.env.MIX_ENV
	}
	command: #"""
		find .
		mix deps.compile
		"""#
	// Directory in which the command is executed
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
