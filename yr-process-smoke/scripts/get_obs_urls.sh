#!/usr/bin/env bash
# Print the OBS wheel + tarball URLs and VERSION for a yuanrong-jcl build.
# The jcl builds expose NO buildkite artifacts; packages live only on OBS,
# referenced in the build's meta_data "obs-urls.*".
#
# Usage: get_obs_urls.sh <build_number> [pipeline]
#        pipeline defaults to $SMOKE_PIPELINE, then yuanrong-jcl
# Env:   BUILDKITE_API_TOKEN (or sourced from ~/.config/yr-buildkite/config.env)
set -euo pipefail
BUILD="${1:?usage: get_obs_urls.sh <build_number> [pipeline]}"
PIPELINE="${2:-${SMOKE_PIPELINE:-yuanrong-jcl}}"
[ -n "${BUILDKITE_API_TOKEN:-}" ] || { set -a; . ~/.config/yr-buildkite/config.env; set +a; }
API="https://api.buildkite.com/v2/organizations/openyuanrong/pipelines/${PIPELINE}/builds/${BUILD}"

json=$(curl -s -H "Authorization: Bearer ${BUILDKITE_API_TOKEN}" "$API")
state=$(echo "$json" | jq -r '.state')
echo "# build #${BUILD} state=${state}" >&2
[ "$state" = "passed" ] || echo "# WARNING: build not passed; OBS packages may be incomplete" >&2

# obs-urls.* values are "filename<TAB>url" lines (one per artifact group)
urls=$(echo "$json" | jq -r '.meta_data | to_entries[] | select(.key|startswith("obs-urls")) | .value' \
        | awk -F'\t' 'NF==2{print $2}')

# version = the +commit suffix on the main wheel
VERSION=$(echo "$urls" | grep -oE 'openyuanrong-[0-9][^/]*\.tar\.gz' | head -1 \
          | sed -E 's/openyuanrong-(.+)\.tar\.gz/\1/; s/%2B/+/')
echo "VERSION=${VERSION}"

# the 6 wheels a process-mode master needs + the tarball (for the actor framework)
pick() { echo "$urls" | grep -E "$1" | head -1 | sed 's/%2B/+/g'; }
echo "WHEEL_openyuanrong=$(pick '/openyuanrong-[0-9].*py3-none.*\.whl')"
echo "WHEEL_runtime=$(pick '/openyuanrong_runtime-.*cp311.*\.whl')"
echo "WHEEL_functionsystem=$(pick '/openyuanrong_functionsystem-.*\.whl')"
echo "WHEEL_datasystem=$(pick '/openyuanrong_datasystem-[0-9].*cp311.*\.whl')"
echo "WHEEL_faas=$(pick '/openyuanrong_faas-.*cp311.*\.whl')"
echo "WHEEL_sdk=$(pick '/openyuanrong_sdk-.*cp311.*\.whl')"
echo "TARBALL=$(pick '/openyuanrong-[0-9].*\.tar\.gz')"
