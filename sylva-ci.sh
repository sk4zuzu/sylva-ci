#!/usr/bin/env bash

: "${SYLVA_CORE:=$1}"

set -ue -o pipefail

ls -lha "$SYLVA_CORE"

DATE="$(ddate +'the %e of %B%, %Y')"
cowsay "Hello, world! Today is $DATE."

for k in 9 8 6 5 4 3 2 1 0; do
  echo $k
  sleep 1
done
