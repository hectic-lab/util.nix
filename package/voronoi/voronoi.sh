#!/bin/sh
# Usage: ./voronoi_data.sh WIDTH HEIGHT "x1,y1 x2,y2 ..."

if [ $# -lt 4 ]; then
  printf 'Usage: %s WIDTH HEIGHT FADE "x1,y1 x2,y2 ..."\n' "$0" >&2
  exit 1
fi

W=$1
H=$2
FADE=$3
PTS=$4
C1=$5
C2=$6

awk \
  -v W="$W" \
  -v H="$H" \
  -v PTS="$PTS" \
  -v FADE="$FADE" \
  -v C1="$C1" \
  -v C2="$C2" \
  -f ./voronoi.awk
