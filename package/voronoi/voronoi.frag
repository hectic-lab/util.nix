#define PTS_N 500
#define

// Author @patriciogv - 2015
// http://patriciogonzalezvivo.com

#ifdef GL_ES
precision mediump float;
#endif

uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;

float random (vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233)))*43758.5453123);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
      vec2 st = gl_FragCoord.xy/u_resolution.xy;

      float rnd = random( st );

      for(i=0;i<PTS_N;i++){
        u = rnd(); v = rnd();
        x = int(x0 + u*ax + v*bx);
        y = int(y0 + u*ay + v*by);
        printf "%d,%d ", x, y;
      }

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

      //gl_FragColor = vec4(vec3(rnd),1.0);
}
