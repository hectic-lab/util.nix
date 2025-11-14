```sh
sh voronoi.sh 500 500 65 "$(sh ./gen-voronoi-points.sh 400 0 0 500 0 0 500)" 0,0,255 255,0,0 \
| magick -size 200x200 xc:white -draw @- voronoi.png
```
