#!/bin/bash
set -eu -o pipefail -o errtrace


function err_trap {
    local err=$?
    local i=0
    local line_number
    local function_name
    local file_name

    set +e

    echo "ERROR: Trap exit code $err at:" >&2

    while caller $i; do ((i++)); done | while read line_number function_name file_name; do
        echo "ERROR: $file_name:$line_number $function_name"
    done >&2

    exit $err
}

trap err_trap ERR


function title {
    cat <<EOF

########################################################################
#
# $*
#

EOF
}
