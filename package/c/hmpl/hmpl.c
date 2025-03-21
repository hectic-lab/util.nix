#include <stdio.h>
#include <stdlib.h>
#include <string.h>
//#include "libhmpl.h"
#include "libhectic.h"

#define KB128 131072

// CREATE OR REPLACE FUNCTION common.render_template_placeholders(result TEXT, context JSONB, prefix CHAR(1) DEFAULT '')
// RETURNS text LANGUAGE plpgsql AS $$
// DECLARE
//   simple_start INT;
//   simple_end INT;
//   simple_key TEXT;
//   replacement TEXT;
//   first_char CHAR(1);
//   _offset INT := 0;
// 
//   start_pattern CHAR(3);
//   start_pattern_length INT;
// BEGIN
//   start_pattern = '{{' || prefix;
//   start_pattern_length = char_length(start_pattern);
// 	 
//   LOOP
//     -- Locate the start of the simple key marker.
//     simple_start := strpos(substring(result from _offset), start_pattern);
//     EXIT WHEN simple_start = 0; -- Exit if no simple marker is found.
//     
//     IF _offset != 0 THEN
//       simple_start := _offset + simple_start - 1;
//     END IF;
// 
//     -- Locate the end of the simple key marker.
//     simple_end := strpos(result, '}}', simple_start);
//     IF simple_end = 0 THEN
//       RAISE EXCEPTION 'Malformed template: missing closing braces for loop start';
//     END IF;
// 
//     simple_key := substring(result from simple_start + start_pattern_length for simple_end - simple_start - start_pattern_length);
// 
// 
//     replacement := eval_value(context, simple_key);
//     RAISE LOG '% := eval_value(%, %)', replacement, context, simple_key;
//     IF replacement IS NULL THEN
//       _offset := simple_start + start_pattern_length;
//       RAISE LOG '% := % + %', _offset, simple_start, start_pattern_length;
//       IF _offset = 0 THEN
//         RAISE EXCEPTION 'Malformed template: offcet cannot be 0';
//       END IF;
//       CONTINUE;
//     END IF;
//     result := replace(
// 	result,
// 	substring(result from simple_start for simple_end - simple_start + 2),
// 	replacement);
//   END LOOP;
// 
//   RETURN result;
// END $$;

void render_template_placeholders(char *text, char *context, char prefix[1]) {
  // start
  char start_pattern[4];
  sprintf(&start_pattern[0], "{{%s", prefix);

  int start_pattern_length = strlen(start_pattern);
  int offset = 0;

  while (1) {
    // find tag start
    char *placeholder_start = strstr(text + offset, start_pattern);
    if (!placeholder_start) {
      break;
    }
  };
}

void render_template(char *text, char *context) {
  render_template_placeholders(text, context, "");
}

int main(void) {
  render_template(text, context);

  return 0;
}
