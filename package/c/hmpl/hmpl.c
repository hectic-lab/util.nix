#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
//#include "libhmpl.h"
#include "chectic.h"
#include "cjson/cJSON.h"

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
//         RAISE EXCEPTION 'Malformed template: offset cannot be 0';
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
char *eval(cJSON *context, const char *key) {
    if (!context || !key) return NULL;
    char *key_copy = strdup(key);
    char *token, *rest = key_copy;
    cJSON *res = context;

    while ((token = strtok_r(rest, ".", &rest))) {
        res = cJSON_GetObjectItemCaseSensitive(res, token);
        if (!res) {
            free(key_copy);
            return NULL;
        }
    }
    free(key_copy);

    if (cJSON_IsString(res) && res->valuestring)
        return strdup(res->valuestring);
    else if (cJSON_IsNumber(res)) {
        char buf[64];
        snprintf(buf, sizeof(buf), "%g", res->valuedouble);
        return strdup(buf);
    }
    return cJSON_PrintUnformatted(res);
}

void substring(const char *src, char *dest, size_t start, size_t len) {
    raise_debug("substring %s from %d to %d", src, start, len);
    size_t srclen = strlen(src);
    if (start >= srclen) {
        dest[0] = '\0';
        return;
    }
    if (start + len > srclen)
        len = srclen - start;
    strncpy(dest, src + start, len);
    dest[len] = '\0';
}

char* replace_substring(const char* src, int start, int end, const char* replacement) {
    raise_debug("replace_substring");
    int src_len = strlen(src);
    int rep_len = strlen(replacement);
    int new_len = src_len - (end - start + 1) + rep_len;

    char* new_str = malloc(new_len + 1);
    if (!new_str) return NULL;

    memcpy(new_str, src, start); // copy before
    memcpy(new_str + start, replacement, rep_len); // insert replacement
    strcpy(new_str + start + rep_len, src + end + 1); // copy after

    return new_str;
}

void render_template_placeholders(char *text, cJSON *context, char prefix[1]) {
  raise_debug("render_template_placeholders");
  // start
  char start_pattern[4];
  sprintf(&start_pattern[0], "{{%s", prefix);

  int start_pattern_length = strlen(start_pattern);
  int offset = 0;

  while (1) {
    // find tag start
    char *placeholder_start = strstr(text + offset, start_pattern);
    if (!placeholder_start) { break; }
    char *releative_start = (size_t)placeholder_start - (size_t)text + start_pattern_length;
    raise_debug("start: %d", releative_start);

    if (offset != 0) {
      placeholder_start += offset - 1;
    }

    char* placeholder_end = strstr(placeholder_start, "}}");
    // TODO: user error instead exaption
    if (!placeholder_end) { raise_exception("Malformed template: missing closing braces for placeholder start"); };
    raise_debug("end: %d", (size_t)placeholder_end - (size_t)text);

    int len = (size_t)placeholder_end - (size_t)placeholder_start - start_pattern_length;
    char* placeholder_key = malloc(len + 1);;
    substring(text, placeholder_key, releative_start, len);
    raise_debug("key: %s", placeholder_key);
    char* replacement = eval(context, placeholder_key);
    raise_debug("%s = eval(%s, %s)", replacement, context, placeholder_key);
    if (!replacement) {
      offset = placeholder_start + start_pattern_length;
      raise_log("offset is %s = %s + %s", offset, placeholder_start, start_pattern_length);
      if (offset = 0) {
        raise_exception("offset cannot be 0 here");
      };
      continue;
    }
    text = replace_substring(text, releative_start - start_pattern_length, releative_start + len + 2 - 1, replacement);
    raise_info(text);
  };
}

void render_template(char *text, cJSON *context) {
  render_template_placeholders(text, context, "");
}

int main(int argc, char *argv[]) {
  init_logger();
  raise_info("start");

  char *text = NULL;
  cJSON *context = cJSON_Parse(strdup(argc > 1 ? argv[1] : "{}"));

  if (argc > 2) {
      text = strdup(argv[2]);
  } else if (!isatty(fileno(stdin))) {
      size_t size = 0;
      ssize_t len = getdelim(&text, &size, '\0', stdin);
      if (len < 0) {
          perror("read stdin");
          free(context);
          return 1;
      }
  }

  if (text) {
    render_template(text, context);
  }

  printf("%s", text);

  free(text);
  free(context);
  return 0;
}
