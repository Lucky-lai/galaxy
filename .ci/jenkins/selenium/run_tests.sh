#!/bin/bash

TEST_DIRECTORY=`dirname $0`

DEFAULT_COMPOSE_PROJECT_NAME=`basename $TEST_DIRECTORY`
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-$DEFAULT_COMPOSE_PROJECT_NAME}
# If in Jenkins environment, append ${BUILD_NUMBER} to project so builds don't interfer.
if [ ! -z "$BUILD_NUMBER" ];
then
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}${BUILD_NUMBER}"
fi
export COMPOSE_PROJECT_NAME

echo "Running Jenkins test from $TEST_DIRECTORY with compose project name $COMPOSE_PROJECT_NAME"

find lib -iname '*pyc' -exec rm -rf {} \;
find test -iname '*pyc' -exec rm -rf {} \;

./scripts/common_startup.sh --dev-wheels

. .venv/bin/activate

pip install docker-compose

# TODO: Let docker-compose pick these at random.
export GALAXY_PORT=`python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'`
export SELENIUM_PORT=`python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'`

export TARGET_ROOT=`pwd`
export TARGET_PATH=/galaxy

cd $TEST_DIRECTORY

echo "Cleaning up previous executions if needed."
docker-compose down | true
docker-compose build galaxy
docker-compose up -d

for service_name in postgres galaxy selenium
do
    echo "Waiting on service ${service_name}"
    while true
    do
        if docker ps | grep -q "${COMPOSE_PROJECT_NAME}_${service_name}"
        then
            echo "Service ${service_name} ready."
            break
        fi
        printf "."
        sleep 1;
    done
done

docker ps | grep -q 'prickly_x'


if [ "$1" = "--debug-running-containers" ];
then
    env
    exit 0
fi

export GALAXY_TEST_EXTERNAL="http://localhost:$GALAXY_PORT/"

echo "Waiting on docker-compose managed Galaxy server - $GALAXY_TEST_EXTERNAL."
while ! curl -s "$GALAXY_TEST_EXTERNAL";
do
    for service_name in postgres galaxy selenium
    do
        if ! docker ps | grep -q "${COMPOSE_PROJECT_NAME}_${service_name}"
        then
            echo "Service ${service_name} stopped, exiting and halting containers."
            docker-compose down | true
            exit 1
        fi
    done

    printf "."
    sleep 4;
done;

# Access Selenium on localhost via port $SELENIUM_PORT
export GALAXY_TEST_SELENIUM_REMOTE=1
export GALAXY_TEST_SELENIUM_REMOTE_PORT="${SELENIUM_PORT}"

# Access Galaxy on localhost via port $GALAXY_PORT
export GALAXY_TEST_PORT="${GALAXY_PORT}"

# Have Selenium access Galaxy at this URL
export GALAXY_TEST_EXTERNAL_FROM_SELENIUM="http://galaxy:8080"

cd ../../..

./run_tests.sh --selenium "$@"
exit_code=$?

cd $TEST_DIRECTORY

docker-compose down

exit $exit_code
