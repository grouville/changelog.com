// STARTING POINT: https://docs.dagger.io/1012/ci
// + ../../../.circleci/config.yml
package ci

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/docker"
	"alpha.dagger.io/os"
	"github.com/thechangelog/dagger/docker2"
)

app:                    dagger.#Artifact
docker_host:            dagger.#Input & {string}
app_container_image:    "thechangelog/runtime:2021-05-29T10.17.12Z"
test_db_container_name: "changelog_test_postgres"

dev_deps: os.#Container & {
	image: docker.#Pull & {
		from: app_container_image
	}
	copy: {
		"/app": from: app
	}
	// 🤔 how can we share /app/deps & /app/_build volumes between os.#Containers?
	// We don't want to re-build deps from scratch if there is a change in app
	// We want to share this across builds
	env: {
		MIX_ENV: "dev"
	}
	command: #"""
		mix do deps.get, deps.compile, compile
		ls -lah _build/$MIX_ENV/lib/phoenix/ebin/*.beam
		"""#
	dir: "/app"
}

test_deps: os.#Container & {
	image: docker.#Pull & {
		from: app_container_image
	}
	copy: {
		"/app": from: app
	}
	// cache: {
	//  "/app/deps":   true
	//  "/app/_build": true
	// }
	env: {
		MIX_ENV: "test"
	}
	command: #"""
		mix do deps.get, deps.compile, compile
		ls -lah _build/$MIX_ENV/lib/phoenix/ebin/*.beam
		"""#
	dir: "/app"
}

prod_deps: os.#Container & {
	image: docker.#Pull & {
		from: app_container_image
	}
	copy: {
		"/app": from: app
	}
	// cache: {
	//  "/app/deps":   true
	//  "/app/_build": true
	// }
	env: {
		MIX_ENV: "prod"
	}
	command: #"""
		mix do deps.get, deps.compile, compile
		ls -lah _build/$MIX_ENV/lib/phoenix/ebin/*.beam
		"""#
	dir: "/app"
}

dev_assets: os.#Container & {
	image: dev_deps
	command: #"""
		yarn install --frozen-lockfile
		yarn run compile
		"""#
	dir: "/app/assets"
}

prod_assets: os.#Container & {
	image: prod_deps
	copy: {
		"/app/assets": from: dev_assets
	}
	env: {
		MIX_ENV: "prod"
	}
	command: "mix phx.digest"
	dir:     "/app"
}

start_test_db: docker2.#Command & {
	host: docker_host
	env: {
		CONTAINER_NAME: test_db_container_name
	}
	command: #"""
		docker container inspect $CONTAINER_NAME \
		  --format 'Container "{{.Name}}" is "{{.State.Status}}"' \
		|| docker container run \
		  --detach --rm --name $CONTAINER_NAME \
		  --publish 127.0.0.1:5432:5432 \
		  --env POSTGRES_USER=postgres \
		  --env POSTGRES_DB=changelog_test \
		  --env POSTGRES_PASSWORD=postgres \
		  circleci/postgres:12.6

		docker container inspect $CONTAINER_NAME \
		  --format 'Container "{{.Name}}" is "{{.State.Status}}"'
		"""#
}

test: os.#Container & {
	always: true
	image:  test_deps
	env: {
		MIX_ENV: "test"
		DEP:     start_test_db.host
	}
	command: "mix test"
	dir:     "/app"
}

stop_test_db: docker2.#Command & {
	host: docker_host
	env: {
		DEP:            test.env.DEP
		CONTAINER_NAME: test_db_container_name
	}
	command: #"""
		docker container stop $CONTAINER_NAME
		"""#
}

prod_dockerfile: ({os.#File & {
	from: prod_deps
	path: "/app/docker/Dockerfile.production"
}}).contents

build_prod_image: docker.#Build & {
	source:     prod_assets
	dockerfile: prod_dockerfile
}

// Publish prod_image to container registry
// remoteImage: docker.#Push & {
//  target: "\(registry):\(tag)"
//  source: image
// }
