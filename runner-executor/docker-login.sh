#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/env

echo "${CI_REGISTRY_PASSWORD}" | docker --config ${1} login -u ${CI_REGISTRY_USER} --password-stdin ${CI_REGISTRY}
rm -rf ${SCRIPT_DIR}/env
