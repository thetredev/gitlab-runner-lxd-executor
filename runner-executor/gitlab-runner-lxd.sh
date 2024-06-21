#!/bin/bash

# See the following link for more details:
# https://docs.gitlab.com/runner/executors/custom_examples/lxd.html


EPHEMERAL_VM_IMAGE="gitlab-runner-lxc-debian"
CONTAINER_ID="runner-${CUSTOM_ENV_CI_RUNNER_ID}-project-${CUSTOM_ENV_CI_PROJECT_ID}-concurrent-${CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID}-${CUSTOM_ENV_CI_JOB_ID}"

CONTAINER_DOCKER_AUTH_PATH=/tmp/gitlab-runner-docker-auth/${CONTAINER_ID}
CONTAINER_DOCKER_AUTH_SCRIPT=${CONTAINER_DOCKER_AUTH_PATH}/auth.sh
CONTAINER_DOCKER_EXE="docker --config ${CONTAINER_DOCKER_AUTH_PATH}/config"


# TODO add services


panic_safely() {
    if [ ${1} -ne 0 ]; then
        echo "RUNNER FAILURE DUE TO: ${1}"

        lxc delete --force ${CONTAINER_ID}
        exit ${SYSTEM_FAILURE_EXIT_CODE}
    fi
}

is_container_image() {
    if [[ "${CUSTOM_ENV_CI_JOB_IMAGE}" =~ "images:" ]]; then
        return 1
    fi

    if [[ "${CUSTOM_ENV_CI_JOB_IMAGE}" =~ "vm:" ]]; then
        return 1
    fi

    return 0
}

prepare_container() {
    echo "Logging in to container registry..."

    mkdir -p ${CONTAINER_DOCKER_AUTH_PATH}
    cat > ${CONTAINER_DOCKER_AUTH_PATH}/env <<EOF
CI_REGISTRY=${CUSTOM_ENV_CI_REGISTRY}
CI_REGISTRY_USER=${CUSTOM_ENV_CI_REGISTRY_USER}
CI_REGISTRY_PASSWORD=${CUSTOM_ENV_CI_REGISTRY_PASSWORD}
EOF
    lxc file push ${CONTAINER_DOCKER_AUTH_PATH}/env ${CONTAINER_ID}/${CONTAINER_DOCKER_AUTH_PATH}/env -p --mode 744
    panic_safely ${?}
    rm -rf ${CONTAINER_DOCKER_AUTH_PATH}

    lxc file push /usr/local/bin/docker-login.sh ${CONTAINER_ID}/${CONTAINER_DOCKER_AUTH_SCRIPT} -p --mode 744
    panic_safely ${?}

    lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_AUTH_SCRIPT} ${CONTAINER_DOCKER_AUTH_PATH}/config
    panic_safely ${?}

    echo "Preparing job container network..."
    lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_EXE} network create ${CONTAINER_ID}
    panic_safely ${?}

    # TODO: services (json from env var)

    echo "Preparing job container..."
    lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_EXE} pull ${CUSTOM_ENV_CI_JOB_IMAGE}
    panic_safely ${?}

    readarray -d '' -t job_container_env < <(env -0 | sed -z 's/^/--env\x00/')

    lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_EXE} run \
        -v /lib/modules:/lib/modules \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /tmp/gitlab-runner-run-stages:/tmp/gitlab-runner-run-stages \
        --device /dev/kvm:/dev/kvm \
        --device /dev/vhost-vsock:/dev/vhost-vsock \
        --device /dev/vhost-net:/dev/vhost-net \
        --detach \
        --privileged \
        --name ${CONTAINER_ID} \
        --network ${CONTAINER_ID} \
        "${job_container_env[@]}" \
        -it ${CUSTOM_ENV_CI_JOB_IMAGE}
    panic_safely ${?}
}

prepare() {
    echo "Cleaning up build environment..."
    lxc delete --force ${CONTAINER_ID}

    echo "Preparing ephemeral build VM..."
    local limits_cpu=$(expr $(nproc) - 2)
    local limits_memory="$(expr $(free -g | grep Mem: | awk '{print $2}') - 2)GiB"

    lxc init ${EPHEMERAL_VM_IMAGE} \
        --config limits.cpu=${limits_cpu} \
        --config limits.memory="${limits_memory}" \
        --config security.secureboot=false \
        -s local \
        ${CONTAINER_ID} \
        --vm
    panic_safely ${?}

    lxc start ${CONTAINER_ID}
    panic_safely ${?}

    local runner_vm_boot_timeout=60
    echo "Waiting at most ${runner_vm_boot_timeout} seconds for the ephemeral build VM to boot up..."

    for i in $(seq 1 ${runner_vm_boot_timeout}); do
        if lxc info ${CONTAINER_ID} | grep -i processes | grep -E '[0-9]' | grep -qv '-'; then
            break
        fi

        if [ "${i}" == "${runner_vm_boot_timeout}" ]; then
            echo "Waited for ${runner_vm_boot_timeout} seconds to start container, exiting.."
            panic_safely 1 ${SYSTEM_FAILURE_EXIT_CODE}
        fi

        sleep 1s
    done

    if is_container_image; then prepare_container; fi
    echo "Ready to rumble!"
}

run() {
    local script_path=${1}
    local script_target="/tmp/gitlab-runner-run-stages/${2}"

    lxc file push ${script_path} ${CONTAINER_ID}${script_target} -p --mode 744
    panic_safely ${?}

    if is_container_image; then
        lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_EXE} exec ${CONTAINER_ID} ${script_target}
        panic_safely ${?} ${BUILD_FAILURE_EXIT_CODE}
    else
        lxc exec ${CONTAINER_ID} -- ${script_target}
        panic_safely ${?} ${BUILD_FAILURE_EXIT_CODE}
    fi

    lxc exec ${CONTAINER_ID} -- rm -rf ${script_target}
}

cleanup() {
    if is_container_image; then
        lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_EXE} rm -f ${CONTAINER_ID}
        lxc exec ${CONTAINER_ID} -- ${CONTAINER_DOCKER_EXE} network rm -f ${CONTAINER_ID}
        lxc exec ${CONTAINER_ID} -- rm -rf ${CONTAINER_DOCKER_AUTH_PATH}
    fi

    rm -rf ${CONTAINER_DOCKER_AUTH_PATH}

    echo "Removing ephemeral build VM..."
    lxc delete --force ${CONTAINER_ID} || true

    echo "Build environment cleaned up"
}


# execute the function based on arguments
${@}
