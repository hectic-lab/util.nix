#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <time.h>
#include <ctype.h>
#include <limits.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define MAX_FILES 1024
#define POLL_INTERVAL_MS 100  // milliseconds

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s <command> <file1> [file2] ...\n", prog_name);
    fprintf(stderr, "   or: find <pattern> | %s <command>\n", prog_name);
    exit(EXIT_FAILURE);
}

struct file_info {
    char *path;
    time_t last_mtime;
    struct stat st;
};

int check_file_modified(struct file_info *file) {
    struct stat new_st;
    if (stat(file->path, &new_st) != 0) {
        perror("stat");
        return -1;
    }

    // Check if file was modified
    if (new_st.st_mtime != file->st.st_mtime) {
        file->st = new_st;
        return 1;
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
    }

    char *command = argv[1];
    struct file_info files[MAX_FILES];
    int num_files = 0;

    // Check if we're getting input from stdin (find command)
    if (!isatty(fileno(stdin))) {
        // Read files from stdin
        char line[PATH_MAX];
        while (fgets(line, sizeof(line), stdin) && num_files < MAX_FILES) {
            // Remove newline and any whitespace
            line[strcspn(line, "\n")] = 0;
            char *end = line + strlen(line) - 1;
            while (end >= line && isspace(*end)) end--;
            *(end + 1) = 0;
            
            if (strlen(line) > 0) {
                files[num_files].path = strdup(line);
                if (!files[num_files].path) {
                    perror("strdup");
                    exit(EXIT_FAILURE);
                }
                if (stat(files[num_files].path, &files[num_files].st) != 0) {
                    perror("stat");
                    fprintf(stderr, "Skipping invalid path: %s\n", line);
                    free(files[num_files].path);
                    continue;
                }
                num_files++;
            }
        }
    } else {
        // No stdin input, use command line arguments
        if (argc < 3) {
            print_usage(argv[0]);
        }
        for (int i = 2; i < argc && num_files < MAX_FILES; i++) {
            files[num_files].path = strdup(argv[i]);
            if (!files[num_files].path) {
                perror("strdup");
                exit(EXIT_FAILURE);
            }
            if (stat(files[num_files].path, &files[num_files].st) != 0) {
                perror("stat");
                fprintf(stderr, "Skipping invalid path: %s\n", argv[i]);
                free(files[num_files].path);
                continue;
            }
            num_files++;
        }
    }

    if (num_files == 0) {
        fprintf(stderr, "No files to watch\n");
        exit(EXIT_FAILURE);
    }

    // Print the files we're watching
    fprintf(stderr, "Watching %d files:\n", num_files);
    for (int i = 0; i < num_files; i++) {
        fprintf(stderr, "  %s\n", files[i].path);
    }

    fprintf(stderr, "Waiting for file modifications...\n");

    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = POLL_INTERVAL_MS * 1000;  // Convert to microseconds

    while (1) {
        // Use select to wait for the specified interval
        select(0, NULL, NULL, NULL, &tv);

        int any_modified = 0;
        for (int i = 0; i < num_files; i++) {
            int modified = check_file_modified(&files[i]);
            if (modified > 0) {
                fprintf(stderr, "File modified: %s\n", files[i].path);
                any_modified = 1;
            } else if (modified < 0) {
                fprintf(stderr, "Error checking file: %s\n", files[i].path);
            }
        }

        if (any_modified) {
            fprintf(stderr, "Executing command: %s\n", command);
            int res = system(command);
            if (res != 0) {
                perror("system");
                exit(EXIT_FAILURE);
            }
        }

        // Reset timeout for next iteration
        tv.tv_sec = 0;
        tv.tv_usec = POLL_INTERVAL_MS * 1000;
    }

    // Cleanup
    for (int i = 0; i < num_files; i++) {
        free(files[i].path);
    }
    return 0;
}