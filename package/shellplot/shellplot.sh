#!/bin/dash
# ImageMagick: scatter plot "by dots" from (x y) data
# - Input: points.txt with "x y" per line (whitespace-separated)
# - Output: plot.png (white bg, black dots). Also draws an optional polyline through points.
# - Quick one-off example (manual coords):
#   magick -size 640x400 xc:white -fill black -draw 'circle 100,100 102,100 circle 200,150 202,150 circle 320,240 322,240' out.png
# stdin→stdout by default; refuse to dump PNG to a tty

W=800 H=600 M=40 R=3
XAXIS=${1:-"X Axis"}
YAXIS=${2:-"Y Axis"}
IN=-
OUT=-

BIN_CONVERT="${BIN_CONVERT:-convert}"

CMD=$(command -v magick >/dev/null 2>&1 && printf "magick" || printf "%s" "$BIN_CONVERT")
FONT_FILE=${FONT_FILE:-$(fc-match -f '%{file}\n' 'DejaVu Sans:style=Book' 2>/dev/null)}
[ -r "$FONT_FILE" ] || { echo "No font found. Install dejavu_fonts and re-run." >&2; exit 1; }
POINTSIZE=${POINTSIZE:-12}

# normalize IO
case "$IN" in
  -|"" )
    INFILE=$(mktemp) || exit 1
    trap 'rm -f "$INFILE"' EXIT
    cat >"$INFILE"                   # buffer stdin once
    ;;
  * )
    INFILE=$IN
    ;;
esac

if [ "$OUT" = "-" ]; then
  [ -t 1 ] && { echo "Refusing to write PNG to terminal." >&2; exit 2; }
  OUT=png:-
fi
# bounds
set -- $(awk 'NR==1{minx=maxx=$1; miny=maxy=$2}
             {if($1<minx)minx=$1; if($1>maxx)maxx=$1; if($2<miny)miny=$2; if($2>maxy)maxy=$2}
             END{print minx, maxx, miny, maxy}' "$INFILE") || exit 1
minx=$1 maxx=$2 miny=$3 maxy=$4
[ "$minx" = "$maxx" ] && maxx=$(awk -v v="$minx" 'BEGIN{print v+1}')
[ "$miny" = "$maxy" ] && maxy=$(awk -v v="$miny" 'BEGIN{print v+1}')

sx=$(awk -v W=$W -v M=$M -v a=$minx -v b=$maxx 'BEGIN{printf "%.10f",(W-2*M)/(b-a)}')
sy=$(awk -v H=$H -v M=$M -v a=$miny -v b=$maxy 'BEGIN{printf "%.10f",(H-2*M)/(b-a)}')

# dots + optional polyline
awk -v W=$W -v H=$H -v M=$M -v R=$R -v minx=$minx -v miny=$miny -v sx=$sx -v sy=$sy '
BEGIN{ print "fill black"; print "stroke none" }
{
  px = M + ( $1 - minx ) * sx;
  py = H - ( M + ( $2 - miny ) * sy );
  printf "circle %.2f,%.2f %.2f,%.2f\n", px, py, px+R, py;
  pts = pts sprintf("%.2f,%.2f ", px, py);
}
END{ print "fill none"; print "stroke black"; printf "polyline %s\n", pts }
' "$INFILE" > /tmp/dots.mvg

# axes + labels
awk -v W=$W -v H=$H -v M=$M \
    -v minx=$minx -v maxx=$maxx -v miny=$miny -v maxy=$maxy -v sx=$sx -v sy=$sy '
BEGIN {
  print "stroke black"; print "fill black";
  printf "line %d,%d %d,%d\n", M, H-M, W-M, H-M;   # x axis
  printf "line %d,%d %d,%d\n", M, H-M, M, M;       # y axis
  nticks=5
  for(i=0;i<=nticks;i++){
    xv=minx+(maxx-minx)*i/nticks; px=M+(xv-minx)*sx; py=H-M
    printf "line %.2f,%.2f %.2f,%.2f\n", px, py, px, py+5
    printf "text %.2f,%.2f '"'"'%s'"'"'\n", px-10, py+20, xv
    yv=miny+(maxy-miny)*i/nticks; px=M; py=H-(M+(yv-miny)*sy)
    printf "line %.2f,%.2f %.2f,%.2f\n", px, py, px-5, py
    printf "text %.2f,%.2f '"'"'%s'"'"'\n", px-35, py+5, yv
  }
  printf "text %.2f,%.2f '"'"'%s'"'"'\n", (W/2), H-5, "'"$XAXIS"'"
  printf "text %.2f,%.2f '"'"'%s'"'"'\n", 15, 25, "'"$YAXIS"'"
}
' > /tmp/axes.mvg

cat /tmp/axes.mvg /tmp/dots.mvg > /tmp/all.mvg

# render
"$CMD" -size ${W}x${H} -font "$FONT_FILE" -pointsize "$POINTSIZE" \
  xc:white -draw @/tmp/all.mvg "$OUT"

# log only when not writing to stdout
[ "$OUT" = "png:-" ] || printf 'wrote %s\n' "$OUT" >&2

