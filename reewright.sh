#!/usr/bin/env bash
set -euxo pipefail

function get_uri() {
    local repo="$1"

    pushd "${repo}" > /dev/null
    local remote_name=$(git remote show | head)
    local remote_url=$(git remote get-url "${remote_name}" | head)
    popd >  /dev/null
    echo "${remote_url}"
}

function get_branch() {
    local repo="$1"

    pushd "${repo}" > /dev/null
    local remote_branch=$(git branch --show-current | head)
    popd  > /dev/null
    echo "${remote_branch}"
}

function gen_pipelines_yaml() {
    local ci_folder="$1"

    pushd "${ci_folder}" >> /dev/null
    local pipes=$(find . -maxdepth 3 -mindepth 3 -name pipeline.yaml)

    for pipe in ${pipes}
    do
        local team=$(echo "${pipe}" | cut -sd / -f 2)
        local name=$(echo "${pipe}" | cut -sd / -f 3)
        echo "
      - set_pipeline: \"${name}\"
        team: \"${team}\"
        file: \".generated/${team}/${name}/pipeline.yaml\"
        "
    done
    popd >> /dev/null
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

pushd "${DIR}"
  PARENT_REPO=$(git rev-parse --show-superproject-working-tree)
  source "${PARENT_REPO}/.reewright"
  CUSTOM_CI_FOLDER="${DIR}/../${ci_folder}"
popd

GEN_YAML=$(cat <<EOF
---
resources:
  - name: repository
    type: git
    source:
      uri: $(get_uri "${PARENT_REPO}")
      branch: $(get_branch "${PARENT_REPO}")

jobs:
  - name: reewright-pipelines
    plan:
      - get: repository
        trigger: true
      - task: generate-yaml
        config:
          run:
            path: repository/.reewright.d/reewright.sh
          platform: linux
          image_resource:
            type: registry-image
            source: { repository: busybox }
          inputs:
            - name: repository
          outputs:
            - name: .generated

      - set_pipeline: self
        file: .generated/reewright.yaml

  - name: set-other-pipelines
    plan:
    - get: repository
      trigger: true
      passed: [ "reewright-pipelines" ]
    - in_parallel:

$(gen_pipelines_yaml "${CUSTOM_CI_FOLDER}")
EOF
)

mkdir -p ".generated"
cp -R "${CUSTOM_CI_FOLDER}/." ".generated"
echo "${GEN_YAML}" > ".generated/reewright.yaml"
