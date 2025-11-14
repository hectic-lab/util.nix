#!/bin/sh
# posix: uniform points in a 2D parallelogram for Voronoi seeds
# usage: ./gen N x0 y0 ax ay bx by
# generates N points p = (x0,y0) + u*(ax,ay) + v*(bx,by), with u,v ~ U[0,1)

[ "$#" -eq 7 ] || { echo "usage: $0 N x0 y0 ax ay bx by" >&2; exit 1; }

awk -v n="$1" -v x0="$2" -v y0="$3" -v ax="$4" -v ay="$5" -v bx="$6" -v by="$7" '
BEGIN{
  srand();
  for(i=0;i<n;i++){
    u = rand(); v = rand();
    x = int(x0 + u*ax + v*bx);
    y = int(y0 + u*ay + v*by);
    printf "%d,%d ", x, y;
  }
}'
