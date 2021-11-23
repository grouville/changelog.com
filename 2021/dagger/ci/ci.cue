// STARTING POINT: https://docs.dagger.io/1012/ci
// + ../../../.circleci/config.yml
package ci

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/dagger/op"
	"alpha.dagger.io/docker"
	"alpha.dagger.io/os"
	"github.com/thechangelog/dagger/docker2"
)

app:                    dagger.#Artifact
prod_dockerfile:        dagger.#Artifact
docker_host:            dagger.#Input & {string}
app_container_image:    "thechangelog/runtime:2021-05-29T10.17.12Z"
test_db_container_name: "changelog_test_postgres"
dockerhub_username:     dagger.#Input & {string}
dockerhub_password:     dagger.#Input & {dagger.#Secret}

// dev_deps | test_deps | prod_deps | start_test_db
// |                  |  /|                  /|
// |                  | / test_prod_assets  / |
// |                  |/                   /  |
// |                  /                   /   |
// |- dev_assets     /|                  /    |
//    |- prod_assets/  \                /     |
//    |                 \-- test ------/      stop_test_db
//    |                     /
//    |- prod_image        /
//       |                /
//       |- publish ------

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
		DEP:     "self"
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
	env: {
		DEP:     "self"
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
		MIX_ENV:              "test"
		DEP:                  start_test_db.host
		"dockerhub_username": dockerhub_username
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

test_prod_assets: os.#Container & {
	always: true
	image:  prod_deps
	command: #"""
		set -x
		ls -lah _build
		ls -lah priv
		mkdir /app2
		cp -r /app /app2
		ls -lah /app
		ls -lah /app2
		"""#
	dir: "/app"
}

// We should only run this step if test succeeds,
// otherwise we would be building a prod artefact for code that fails tests
prod_image: {
	#up: [
		op.#Load & {
			from: prod_assets
		},
		op.#DockerBuild & {
			// Why does this context re-run previous steps?
			// Rather than running mix, yarn commands etc. it should consume the result of those steps
			context:    prod_assets
			dockerfile: prod_dockerfile
		},
	]
}

publish: docker.#Push & {
	auth: {
		username: test.env.dockerhub_username
		secret:   dockerhub_password
	}
	source: prod_image
	target: "thechangelog/changelog.com:dagger"
}

// Publish prod_image to container registry
// remoteImage: docker.#Push & {
//  target: "\(registry):\(tag)"
//  source: image
// }
