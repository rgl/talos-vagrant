#!/bin/bash
set -eu -o pipefail -o errtrace


function title {
    cat <<EOF

##$(date --iso-8601=s)######################################################################
#
# $*
#

EOF
}
