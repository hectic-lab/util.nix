function clamp(v){ return v<0?0:(v>1?1:v) }
function color_lerp(p, q, r1, g1, b1, r2, g2, b3, x){
  t = (x - p) / (q - p)
  t = clamp(t)
  r = int(r1 + t*(r2 - r1) + 0.5)
  g = int(g1 + t*(g2 - g1) + 0.5)
  b = int(b1 + t*(b2 - b1) + 0.5)
  return sprintf("#%02X%02X%02X", r, g, b)
}
BEGIN {
  # external variables
  # PTS  is voronoi centers
  # W    is canvas width
  # H    is canvas height
  # FADE is fade max distance
  # C1   is first color in gradient
  # C2   is secont color in gradient

  if (C1 == "") C1 = "0,0,0"
  if (C2 == "") C2 = "255,255,255"
  split(C1, c1, ",")
  split(C2, c2, ",")

  n = split(PTS, pairs, " ")
  for (i = 1; i <= n; ++i) {
    split(pairs[i], xy, ",")
    px[i] = xy[1] + 0
    py[i] = xy[2] + 0
  }

  for (y = 0; y < H; y++)
    for (x = 0; x < W; x++) {
      min_d = 1e308
      for (i = 1; i <= n; i++) {
        dx = x - px[i]
        dy = y - py[i]
        d = sqrt(dx*dx + dy*dy)
        if (d < min_d)
          min_d = d
      }

      fade = FADE - min_d
      if (fade < 0) fade = 0

      color = color_lerp(0, FADE, c1[1],c1[2],c1[3], c2[1],c2[2],c2[3], fade)

      printf "fill %s point %d,%d\n", color, x, y
    }
}
