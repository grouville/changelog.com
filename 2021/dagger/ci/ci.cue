// STARTING POINT: https://docs.dagger.io/1012/ci
// + ../../../.circleci/config.yml
package ci

import (
	"alpha.dagger.io/dagger"
	"alpha.dagger.io/dagger/op"
	"alpha.dagger.io/docker"
	"alpha.dagger.io/http"
	"alpha.dagger.io/os"
	// "github.com/thechangelog/dagger/docker2"
)

app:                    dagger.#Artifact
prod_dockerfile:        dagger.#Artifact
docker_socket:          dagger.#Input & {dagger.#Stream}
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

start_test_db: docker.#Command & {
	socket: docker_socket
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
		DEP:                  start_test_db.env.CONTAINER_NAME
		"dockerhub_username": dockerhub_username
		forced_dependency: "localhost:5042" // Forced dependency here for local version
	}
	command: "mix test"
	dir:     "/app"
}

stop_test_db: docker.#Command & {
	socket: docker_socket
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

// Build image eagerly, but only publish if test succeeds
prod_image: {
	#up: [
		// op.#Load & {
		// 	from: prod_assets
		// },
		op.#DockerBuild & {
			// Why does this context re-run previous steps?
			// Rather than running mix, yarn commands etc. it should consume the result of those steps
			context:    prod_assets
			dockerfile: prod_dockerfile
			// platforms: ["linux/amd64"]
			// buildArg: {
			// 	// TODO: Get from input
			// 	"APP_VERSION": "21.11.25+4f925cc"
			// 	// TODO: Get from input
			// 	"GIT_SHA": "4f925cce08433b9a779196590d0064b665b7f14a"
			// 	// TODO: Get from input
			// 	"GIT_AUTHOR": "gerhard"
			// 	// TODO: Get from input
			// 	"BUILD_URL": "https://circleci.com/gh/thechangelog/changelog.com/4678"
			// }
		},
	]
}
// No use op.#DockerBuild, use the docker engine instead
// Start w result of prod_asset, we take the Prod_dockerfile, and we build our final image
// eq to start_test_db

//  Replaced by change below
// publish: docker.#Push & {
// 	auth: {
// 		username: test.env.dockerhub_username
// 		secret:   dockerhub_password
// 	}
// 	source: prod_image
// 	target: "thechangelog/changelog.com:dagger"
// }


// run our local registry
registry: docker.#Run & {
	ref:  "registry:2"
	name: "registry-local"
	ports: ["5042:5000"]
	socket: docker_socket
}

// // As we pushed the registry to our local docker
// we need to wait for the container to be up
wait: http.#Wait & {
	url: test.env.forced_dependency // dependency on test created here
	startPeriod: 30
}

// push the image to a registry
publish: docker.#Push & {
	// leave target blank here so that different
	// environments can push to different registries
	target: "\(wait.url)/changelog" // dependency on runnin container here

	// the source of our push resource
	// is the image resource we declared above
	source: prod_image
}
