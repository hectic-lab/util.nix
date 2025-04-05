#include <stdio.h>
#include <string.h>
#include <hectic.h>
#include <strings.h>
#include <stdlib.h>
#include <getopt.h>

#define MAX_LINE 1024

typedef struct {
    const char *keyword;
    const char *color;
} KeywordColor;

static KeywordColor keyword_colors[] = {
    {"LOG", COLOR_GREEN},
    {"DEBUG", COLOR_BLUE},
    {"ERROR", COLOR_RED},
    {"INFO", COLOR_GREEN},
    {"WARNING", COLOR_YELLOW},
    {"NOTICE", COLOR_CYAN},
    {"HINT", COLOR_MAGENTA},
    {"DETAIL", COLOR_CYAN},
    {"STATEMENT", COLOR_CYAN},
    {"EXCEPTION", COLOR_MAGENTA},
    {"FATAL", COLOR_MAGENTA},
};

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s [options]\n", prog_name);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -i, --ignore-case    Ignore case when matching keywords (default)\n");
    fprintf(stderr, "  -h, --help           Display this help message\n");
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[]) {
    // Default to case-insensitive matching
    int ignore_case = 0;
    
    // Define long options
    static struct option long_options[] = {
        {"ignore-case", no_argument, NULL, 'i'},
        {"help", no_argument, NULL, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "ih", long_options, NULL)) != -1) {
        switch (opt) {
            case 'i':
                ignore_case = 1;
                break;
            case 'h':
            default:
                print_usage(argv[0]);
                break;
        }
    }

    char line[MAX_LINE];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        char *space = strchr(line, ' ');
        char token[MAX_LINE];
        if (space) {
            int len = space - line;
            strncpy(token, line, len);
            token[len] = '\0';
        } else {
            strcpy(token, line);
        }
        const char *color = "";
        int count = sizeof(keyword_colors) / sizeof(keyword_colors[0]);
        for (int i = 0; i < count; i++) {
            // Use either case-sensitive or case-insensitive comparison based on the option
            int match = ignore_case ? 
                strcasecmp(token, keyword_colors[i].keyword) == 0 :
                strcmp(token, keyword_colors[i].keyword) == 0;
                
            if (match) {
                color = keyword_colors[i].color;
                break;
            }
        }
        if (color[0] != '\0')
            printf("%s%s%s", color, token, COLOR_RESET);
        else
            printf("%s", token);
        if (space)
            printf("%s", space);
        printf("\n");
    }
    return 0;
}