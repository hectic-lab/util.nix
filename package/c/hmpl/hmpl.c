#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "chectic.h"
#include "cjson/cJSON.h"

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
    raise_debug("substring %s from %zu to %zu", src, start, len);
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

    memcpy(new_str, src, start);                     // copy before
    memcpy(new_str + start, replacement, rep_len);     // insert replacement
    strcpy(new_str + start + rep_len, src + end + 1);    // copy after

    return new_str;
}

/* Modified: text is passed by reference so we can update it and free old allocations */
void render_template_placeholders(char **text_ptr, cJSON *context, const char *prefix) {
    raise_debug("render_template_placeholders");
    char start_pattern[256];
    snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix);
    int start_pattern_length = strlen(start_pattern);
    int offset = 0;

    while (1) {
        char *current_text = *text_ptr;
        char *placeholder_start = strstr(current_text + offset, start_pattern);
        if (!placeholder_start)
            break;
        int start_index = placeholder_start - current_text;
        int key_start = start_index + start_pattern_length;
        raise_debug("start: %d", key_start);

        char *placeholder_end = strstr(placeholder_start, "}}");
        if (!placeholder_end) {
            raise_exception("Malformed template: missing closing braces for placeholder start");
        }
        int key_length = (placeholder_end - current_text) - key_start;
        char *placeholder_key = malloc(key_length + 1);
        if (!placeholder_key)
            raise_exception("Memory allocation error");
        substring(current_text, placeholder_key, key_start, key_length);
        raise_debug("key: %s", placeholder_key);

        char *replacement = eval(context, placeholder_key);
        raise_debug("%s = eval(context, %s)", replacement ? replacement : "NULL", placeholder_key);
        free(placeholder_key);
        if (!replacement) {
            offset = (placeholder_end - current_text) + 2; // skip past the placeholder
            continue;
        }
        int placeholder_end_index = (placeholder_end - current_text) + 2; // include "}}"

        char *new_text =
	  replace_substring(current_text, start_index, placeholder_end_index - 1, replacement);
        free(replacement);
        free(current_text);    // free the old text
			       
        *text_ptr = new_text;
        offset = start_index;  // resume search from the replaced location
    }
}

void render_template(char **text, cJSON *context) {
    render_template_placeholders(text, context, "");
}

int main(int argc, char *argv[]) {
    init_logger();
    raise_info("start");

    char *text = NULL;
    const char *json_input = (argc > 1 ? argv[1] : "{}");
    cJSON *context = cJSON_Parse(json_input);
    if (!context) {
        fprintf(stderr, "Error parsing JSON\n");
        return 1;
    }

    if (argc > 2) {
        text = strdup(argv[2]);
    } else if (!isatty(fileno(stdin))) {
        size_t size = 0;
        ssize_t len = getdelim(&text, &size, '\0', stdin);
        if (len < 0) {
            perror("read stdin");
            cJSON_Delete(context);
            return 1;
        }
    } else {
        text = strdup("");
    }

    render_template(&text, context);
    printf("%s", text);

    free(text);
    cJSON_Delete(context);
    return 0;
}
