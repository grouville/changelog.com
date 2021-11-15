// STARTING POINT: https://docs.dagger.io/1012/ci
// + ../../../.circleci/config.yml
package ci

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/docker"
	"alpha.dagger.io/os"
)

app: dagger.#Artifact

app_env: string

deps_get: os.#Container & {
	image: docker.#Pull & {
		from: "thechangelog/runtime:2021-05-29T10.17.12Z"
	}
	copy: {
		"/app": from: app
	}
	env: {
		MIX_ENV: app_env
	}
	command: #"""
		mix deps.get
		"""#
	dir: "/app"
}
deps_compile: os.#Container & {
	image: deps_get
	env: {
		MIX_ENV: app_env
	}
	command: #"""
		mix deps.compile
		"""#
	dir: "/app"
}

deps_compile_check: os.#Container & {
	always: true
	image:  deps_compile
	env: {
		MIX_ENV: app_env
	}
	command: "ls -lah _build/\(app_env)/lib/phoenix/ebin/*.beam"
	dir:     "/app"
}
