#!/bin/bash

#
# Author: Daniel Dietrich
# Contact: cafebab3@gmail.com
#

# immediately exit if a function call fails
set -e

# commands
CURL="curl --silent"
NODE="node"

# locations
GIT_CONFIG="$HOME/.gitconfig"
NPM_REPOSITORY=".npm-private" # no trailing slash '/'

function json() {
    JSON=$1
    SELECTOR=$2
    if [ "${JSON}" == "undefined" ]; then
        echo "undefined"
    else
        RESULT=$(${NODE} -p "JSON.stringify(JSON.parse(process.argv[1])[process.argv[2]], null, 2)" "$JSON" "$SELECTOR")
        if [[ $? -ne 0 ]]; then
            (>&2 echo "💥 ERROR: Parsing JSON")
            (>&2 echo "$RESULT")
            exit 1
        else
            echo "$RESULT"
        fi
    fi
}

function jsonValue() {
    JSON=$1
    if [ "${JSON}" == "undefined" ]; then
        echo "undefined"
    else
        RESULT=$(${NODE} -p "JSON.parse(process.argv[1])" "$JSON")
        if [[ $? -ne 0 ]]; then
            (>&2 echo "💥 ERROR: Parsing JSON value")
            (>&2 echo "$RESULT")
            exit 1
        else
            echo "$RESULT"
        fi
    fi
}

# TODO: consider [GitHub] section of GIT_CONFIG only (ignoring case)
function ghToken() {
    if [ -z "$GITHUB_TOKEN" ]; then
        if [ -f "$GIT_CONFIG" ]; then
            GITHUB_TOKEN=$(grep token < "${GIT_CONFIG}" | awk '{ print $3 }')
            if [ -z "$GITHUB_TOKEN" ]; then
                (>&2 echo "💥 ERROR: Environment variable GITHUB_TOKEN not set and git config ${GIT_CONFIG} does not contain a GitHub access token.")
                exit 1
            else
                echo "$GITHUB_TOKEN"
            fi
        else
            (>&2 echo "💥 ERROR: Environment variable GITHUB_TOKEN not set and git config ${GIT_CONFIG} not found.")
            exit 1
        fi
    else
        echo "$GITHUB_TOKEN"
    fi
}

function ghRelease() {
    GITHUB_ORG=$1
    GITHUB_REPO=$2
    TAG_NAME=$(if [ -z "$3" ]; then echo "latest"; else echo "tags/$3"; fi)
    RELEASE=$(${CURL} -H "Authorization: token ${GITHUB_TOKEN}" https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/releases/${TAG_NAME})
    if [[ $? -ne 0 ]]; then
        TAG_NAME=$(if [ -z "$3" ]; then echo "latest"; else echo "tag/$3"; fi)
        (>&2 echo "💥 ERROR: Fetching latest release of https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/${TAG_NAME}")
        (>&2 echo "$RELEASE")
        exit 1
    else
        echo "${RELEASE}"
    fi
}

function ghDownloadUrl() {
    CONTENT_TYPE=$1
    ASSET_URL=$2
    RESPONSE=$(${CURL} -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept:${CONTENT_TYPE}" -i "${ASSET_URL}")
    if [[ $? -ne 0 ]]; then
        (>&2 echo "💥 ERROR: Fetching download url for asset ${ASSET_URL}")
        (>&2 echo "$RESPONSE")
        exit 1
    fi
    DOWNLOAD_URL=$(echo "$RESPONSE" | grep location | awk '{ print $2 }')
    if [ -z "$DOWNLOAD_URL" ]; then
        (>&2 echo "💥 ERROR: Missing 'location' containing download url of GitHub asset ${ASSET_URL}")
        (>&2 echo "$RESPONSE")
        exit 1
    else
        echo "$DOWNLOAD_URL"
    fi
}

function ghDownloadAsset() {
    DOWNLOAD_URL=$1
    TARGET_PATH=$2
    TARGET_FILE=$3
    TARGET="${TARGET_PATH}/${TARGET_FILE}"
    if [ ! -d "${TARGET_PATH}" ]; then
        mkdir -p "${TARGET_PATH}"
    fi
    if [ ! -d "${TARGET_PATH}" ]; then
        (>&2 echo "💥 ERROR: Creating directory ${TARGET_PATH}")
        exit 1
    else
        RESPONSE=$(${CURL} "${DOWNLOAD_URL%?}" > "${TARGET}")
        if [[ $? -ne 0 ]]; then
            (>&2 echo "💥 ERROR: Dowloading GitHub asset ${DOWNLOAD_URL} to ${TARGET}")
            (>&2 echo "${RESPONSE}")
            exit 1
        fi
    fi
}

function ghCheckForUpdates() {
    GITHUB_ORG=$1
    GITHUB_REPO=$2
    TAG_NAME=$3
    LATEST_RELEASE=$(ghRelease "${GITHUB_ORG}" "${GITHUB_REPO}")
    LATEST_TAG_NAME=$(jsonValue "$(json "${LATEST_RELEASE}" "tag_name")")
    if [ "${LATEST_TAG_NAME}" == "undefined" ]; then
        echo "💣 WARN: No release found for https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
    else
        if [ "${LATEST_TAG_NAME}" \> "${TAG_NAME}" ]; then
           echo "💣 WARN: Newer release of https://github.com/${GITHUB_ORG}/${GITHUB_REPO} found: ${TAG_NAME} -> ${LATEST_TAG_NAME}"
        fi
    fi
}

function ghDownload() {
    GITHUB_ORG=$1
    GITHUB_REPO=$2
    TAG_NAME=$3
    ASSET_NAME=$4
    RELEASE=$(ghRelease "${GITHUB_ORG}" "${GITHUB_REPO}" "${TAG_NAME}")
    ASSETS=$(json "${RELEASE}" "assets")
    ASSET_COUNT=$(${NODE} -p "JSON.parse(process.argv[1]).length" "$ASSETS")
    if [ "$ASSET_COUNT" -eq 0 ]; then
        (>&2 echo "💥 ERROR: Release https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/tag/${TAG_NAME} has no assets")
        exit 1
    fi
    FOUND=0
    for (( i = 0; i < "$ASSET_COUNT"; i++ )); do
        ASSET=$(json "${ASSETS}" "$i")
        CONTENT_TYPE=$(jsonValue "$(json "${ASSET}" "content_type")")
        FILE_NAME=$(jsonValue "$(json "${ASSET}" "name")")
        if [ "$ASSET_NAME" == "$FILE_NAME" ]; then
            echo "☕️ Downloading https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/${TAG_NAME}/${FILE_NAME}"
            ASSET_URL=$(jsonValue "$(json "${ASSET}" "url")")
            DOWNLOAD_URL=$(ghDownloadUrl "${CONTENT_TYPE}" "${ASSET_URL}")
            ghDownloadAsset "${DOWNLOAD_URL}" "${NPM_REPOSITORY}/${GITHUB_ORG}/${GITHUB_REPO}/${TAG_NAME}" "${FILE_NAME}"
            FOUND=1
        fi
    done
    if [ "$FOUND" -eq 0 ]; then
        (>&2 echo "💥 ERROR: Release https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/tag/${TAG_NAME} has no asset ${ASSET_NAME}")
        exit 1
    fi
}

echo "🚀 Pre-processing private dependencies hosted on GitHub"

# read github token
GITHUB_TOKEN=$(ghToken)

# download dependencies
DEPENDENCIES=$(grep "file:${NPM_REPOSITORY}/" < package.json | awk '{ print $2 }')

if [ -z "${DEPENDENCIES}" ]; then
    echo "☕️ No private dependencies found."
else
    while read -r DEPENDENCY; do

        # parse dependency
        IFS='/"' read -ra ARRAY <<< "$DEPENDENCY"
        GITHUB_ORG="${ARRAY[2]}"
        GITHUB_REPO="${ARRAY[3]}"
        TAG_NAME="${ARRAY[4]}"
        ASSET_NAME="${ARRAY[5]}"

        ghCheckForUpdates "${GITHUB_ORG}" "${GITHUB_REPO}" "${TAG_NAME}"

        if [ ! -f "${NPM_REPOSITORY}/${GITHUB_ORG}/${GITHUB_REPO}/${TAG_NAME}/${ASSET_NAME}" ]; then
            ghDownload "${GITHUB_ORG}" "${GITHUB_REPO}" "${TAG_NAME}" "${ASSET_NAME}"
        fi

    done <<< "$DEPENDENCIES"
fi

echo "👍 Done!"
