#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <time.h>
#include <dirent.h>
#include <fnmatch.h>
#include <getopt.h>
#include <ctype.h>
#include <fcntl.h>
#include <signal.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define MAX_DIRS 1024
#define MAX_FILES 10240
#define MAX_PATTERNS 32
#define POLL_INTERVAL_MS 100

// Global flags
int pager_mode = 0;
int ignore_errors = 0;
FILE *output_stream = NULL;
int running = 1;

void signal_handler(int sig) {
    (void)sig; // Mark parameter as used to avoid warning
    running = 0;
}

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s <command> [-p <pattern1>] [-p <pattern2>] ... <dir1> [dir2] ...\n", prog_name);
    fprintf(stderr, "   or: find . -type d | %s <command> [-p <pattern1>] [-p <pattern2>] ...\n", prog_name);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -p <pattern>    File pattern to watch (can be used multiple times)\n");
    fprintf(stderr, "  -P              Enable pager-friendly output (refresh mode)\n");
    fprintf(stderr, "  -i, --ignore-errors  Continue watching even when command returns non-zero\n");
    fprintf(stderr, "  -h              Show this help message\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s 'make' -p '*.c' -p '*.h' ./src\n", prog_name);
    fprintf(stderr, "  find . -type d | %s 'echo changed' -p '*.py'\n", prog_name);
    fprintf(stderr, "  %s -P 'make' -p '*.c' -p '*.h' ./src | less\n", prog_name);
    fprintf(stderr, "  %s -i 'sh ./make.sh check' -p '*.c' -p '*.h' .\n", prog_name);
    exit(EXIT_FAILURE);
}

struct file_info {
    char *path;
    time_t mtime;
    int exists;
};

struct dir_info {
    char *path;
    time_t mtime;
    struct stat st;
};

struct file_hash {
    struct file_info **items;
    int size;
    int count;
};

void hash_init(struct file_hash *hash, int size) {
    hash->size = size;
    hash->count = 0;
    hash->items = calloc(size, sizeof(struct file_info*));
}

unsigned int hash_function(const char *str) {
    unsigned int hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;
    return hash;
}

void hash_insert(struct file_hash *hash, struct file_info *item) {
    if (hash->count >= hash->size * 0.75) {
        fprintf(stderr, "Warning: Hash table full, performance may degrade\n");
    }
    
    unsigned int index = hash_function(item->path) % hash->size;
    
    while (hash->items[index] != NULL) {
        if (strcmp(hash->items[index]->path, item->path) == 0) {
            hash->items[index]->mtime = item->mtime;
            hash->items[index]->exists = item->exists;
            free(item->path);
            free(item);
            return;
        }
        index = (index + 1) % hash->size;
    }
    
    hash->items[index] = item;
    hash->count++;
}

struct file_info *hash_find(struct file_hash *hash, const char *path) {
    unsigned int index = hash_function(path) % hash->size;
    
    int i = 0;
    while (hash->items[index] != NULL && i < hash->size) {
        if (strcmp(hash->items[index]->path, path) == 0) {
            return hash->items[index];
        }
        index = (index + 1) % hash->size;
        i++;
    }
    
    return NULL;
}

void hash_remove_nonexistent(struct file_hash *hash) {
    for (int i = 0; i < hash->size; i++) {
        if (hash->items[i] != NULL && hash->items[i]->exists == 0) {
            free(hash->items[i]->path);
            free(hash->items[i]);
            hash->items[i] = NULL;
            hash->count--;
        }
    }
}

void hash_free(struct file_hash *hash) {
    for (int i = 0; i < hash->size; i++) {
        if (hash->items[i] != NULL) {
            free(hash->items[i]->path);
            free(hash->items[i]);
        }
    }
    free(hash->items);
}

int is_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0)
        return 0;
    return S_ISDIR(st.st_mode);
}

int check_dir_modified(struct dir_info *dir) {
    struct stat new_st;
    if (stat(dir->path, &new_st) != 0) {
        perror("stat");
        return -1;
    }

    return 1;
}

int match_any_pattern(const char *filename, char **patterns, int num_patterns) {
    for (int i = 0; i < num_patterns; i++) {
        if (fnmatch(patterns[i], filename, 0) == 0) {
            return 1;
        }
    }
    return 0;
}

int main(int argc, char *argv[]) {
    // Register signal handlers
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    if (argc < 2) {
        print_usage(argv[0]);
    }

    char *command = argv[1];
    char **patterns = malloc(MAX_PATTERNS * sizeof(char*));
    int num_patterns = 0;
    
    // Define long options
    static struct option long_options[] = {
        {"ignore-errors", no_argument, NULL, 'i'},
        {0, 0, 0, 0}
    };
    
    optind = 2;
    int opt;
    
    while ((opt = getopt_long(argc, argv, "p:Phi", long_options, NULL)) != -1) {
        switch (opt) {
            case 'p':
                if (num_patterns < MAX_PATTERNS) {
                    patterns[num_patterns++] = strdup(optarg);
                } else {
                    fprintf(stderr, "Too many patterns (max %d)\n", MAX_PATTERNS);
                    exit(EXIT_FAILURE);
                }
                break;
            case 'P':
                pager_mode = 1;
                break;
            case 'i':
                ignore_errors = 1;
                break;
            case 'h':
                print_usage(argv[0]);
                break;
            default:
                fprintf(stderr, "Unknown option: %c\n", opt);
                print_usage(argv[0]);
        }
    }
    
    if (num_patterns == 0) {
        fprintf(stderr, "No patterns specified. Use -p option to specify patterns.\n");
        print_usage(argv[0]);
    }
    
    // Set output stream - stderr for normal mode, stdout for pager mode
    output_stream = pager_mode ? stdout : stderr;
    
    // Check if stdout is being piped and we're not in pager mode
    if (!pager_mode && !isatty(STDOUT_FILENO)) {
        pager_mode = 1;
        output_stream = stdout;
    }

    struct dir_info dirs[MAX_DIRS];
    int num_dirs = 0;
    struct file_hash files;
    
    hash_init(&files, MAX_FILES);

    // Check if we're getting input from stdin
    if (!isatty(fileno(stdin))) {
        // Read directories from stdin
        char line[PATH_MAX];
        while (fgets(line, sizeof(line), stdin) && num_dirs < MAX_DIRS) {
            // Remove newline and any whitespace
            line[strcspn(line, "\n")] = 0;
            char *end = line + strlen(line) - 1;
            while (end >= line && isspace(*end)) end--;
            *(end + 1) = 0;
            
            if (strlen(line) > 0 && is_dir(line)) {
                dirs[num_dirs].path = strdup(line);
                if (!dirs[num_dirs].path) {
                    perror("strdup");
                    exit(EXIT_FAILURE);
                }
                if (stat(dirs[num_dirs].path, &dirs[num_dirs].st) != 0) {
                    perror("stat");
                    fprintf(stderr, "Skipping invalid directory: %s\n", line);
                    free(dirs[num_dirs].path);
                    continue;
                }
                num_dirs++;
            }
        }
    } else {
        for (int i = optind; i < argc && num_dirs < MAX_DIRS; i++) {
            if (is_dir(argv[i])) {
                dirs[num_dirs].path = strdup(argv[i]);
                if (!dirs[num_dirs].path) {
                    perror("strdup");
                    exit(EXIT_FAILURE);
                }
                if (stat(dirs[num_dirs].path, &dirs[num_dirs].st) != 0) {
                    perror("stat");
                    fprintf(stderr, "Skipping invalid directory: %s\n", argv[i]);
                    free(dirs[num_dirs].path);
                    continue;
                }
                num_dirs++;
            } else {
                fprintf(stderr, "Skipping non-directory: %s\n", argv[i]);
            }
        }
    }

    if (num_dirs == 0) {
        fprintf(stderr, "No directories to watch\n");
        exit(EXIT_FAILURE);
    }

    // Print the directories and patterns we're watching
    fprintf(output_stream, "Watching %d directories for files matching: ", num_dirs);
    for (int i = 0; i < num_patterns; i++) {
        fprintf(output_stream, "'%s'%s", patterns[i], (i < num_patterns - 1) ? ", " : "\n");
    }
    
    for (int i = 0; i < num_dirs; i++) {
        fprintf(output_stream, "  %s\n", dirs[i].path);
    }
    
    for (int i = 0; i < num_dirs; i++) {
        DIR *dir = opendir(dirs[i].path);
        if (!dir) {
            perror("opendir");
            continue;
        }
        
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') continue;
            
            if (match_any_pattern(entry->d_name, patterns, num_patterns)) {
                char filepath[PATH_MAX];
                snprintf(filepath, PATH_MAX, "%s/%s", dirs[i].path, entry->d_name);
                
                struct stat st;
                if (stat(filepath, &st) != 0) continue;
                if (S_ISDIR(st.st_mode)) continue;
                
                struct file_info *file = malloc(sizeof(struct file_info));
                file->path = strdup(filepath);
                file->mtime = st.st_mtime;
                file->exists = 1;
                
                hash_insert(&files, file);
            }
        }
        closedir(dir);
    }
    
    fprintf(output_stream, "Initially found %d matching files\n", files.count);
    fprintf(output_stream, "Waiting for file modifications...\n");
    fflush(output_stream);

    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = POLL_INTERVAL_MS * 1000; 

    for (int i = 0; i < files.size; i++) {
        if (files.items[i] != NULL) {
            files.items[i]->exists = 1;
        }
    }
    
    tv.tv_sec = 1;
    select(0, NULL, NULL, NULL, &tv);

    tv.tv_sec = 0;
    tv.tv_usec = POLL_INTERVAL_MS * 1000;
    
    int first_scan = 1;
    
    // Main watch loop
    while (running) {
        select(0, NULL, NULL, NULL, &tv);
        
        int any_changes = 0;
        
        for (int i = 0; i < files.size; i++) {
            if (files.items[i] != NULL) {
                files.items[i]->exists = 0;
            }
        }
        
        for (int i = 0; i < num_dirs; i++) {
            DIR *dir = opendir(dirs[i].path);
            if (!dir) {
                perror("opendir");
                continue;
            }
            
            struct dirent *entry;
            while ((entry = readdir(dir)) != NULL) {
                if (entry->d_name[0] == '.') continue;
                
                if (match_any_pattern(entry->d_name, patterns, num_patterns)) {
                    char filepath[PATH_MAX];
                    snprintf(filepath, PATH_MAX, "%s/%s", dirs[i].path, entry->d_name);
                    
                    struct stat st;
                    if (stat(filepath, &st) != 0) continue;
                    if (S_ISDIR(st.st_mode)) continue;
                    
                    struct file_info *existing = hash_find(&files, filepath);
                    if (existing) {
                        existing->exists = 1;
                        if (existing->mtime != st.st_mtime) {
                            if (!first_scan) {
                                fprintf(output_stream, "File modified: %s\n", filepath);
                                any_changes = 1;
                            }
                            existing->mtime = st.st_mtime;
                        }
                    } else {
                        if (!first_scan) {
                            fprintf(output_stream, "New file: %s\n", filepath);
                            any_changes = 1;
                        }
                        struct file_info *file = malloc(sizeof(struct file_info));
                        file->path = strdup(filepath);
                        file->mtime = st.st_mtime;
                        file->exists = 1;
                        hash_insert(&files, file);
                    }
                }
            }
            closedir(dir);
        }
        
        for (int i = 0; i < files.size; i++) {
            if (files.items[i] != NULL && files.items[i]->exists == 0) {
                if (!first_scan) {
                    fprintf(output_stream, "File deleted: %s\n", files.items[i]->path);
                    any_changes = 1;
                }
            }
        }
        
        hash_remove_nonexistent(&files);
        
        // If in pager mode and any changes occur, clear screen and reprint status
        if (pager_mode && any_changes) {
            // Use ANSI escape codes to clear screen
            fprintf(output_stream, "\033[2J\033[H");
            
            // Reprint header
            fprintf(output_stream, "Watching %d directories for files matching: ", num_dirs);
            for (int i = 0; i < num_patterns; i++) {
                fprintf(output_stream, "'%s'%s", patterns[i], (i < num_patterns - 1) ? ", " : "\n");
            }
            
            // List current files
            fprintf(output_stream, "Currently watching %d files:\n", files.count);
            int file_count = 0;
            for (int i = 0; i < files.size && file_count < files.count; i++) {
                if (files.items[i] != NULL) {
                    fprintf(output_stream, "  %s\n", files.items[i]->path);
                    file_count++;
                }
            }
            
            // Show last action
            time_t current_time = time(NULL);
            fprintf(output_stream, "\nLast event: Command executed at %s", ctime(&current_time));
            fprintf(output_stream, "Command: %s\n", command);
            
            // Make sure output is flushed to the pager
            fflush(output_stream);
        } else if (any_changes) {
            // In normal mode, just show status messages
            fprintf(output_stream, "Executing command: %s\n", command);
            fflush(output_stream);
        }
        
        // Execute command if changes detected
        if (any_changes) {
            int res = system(command);
            if (res != 0) {
                time_t current_time = time(NULL);
                fprintf(output_stream, "Command failed at %s", ctime(&current_time));
                fprintf(output_stream, "Command: %s (exit code: %d)\n", command, res);
                fflush(output_stream);
                
                if (!ignore_errors) {
                    fprintf(output_stream, "Exiting due to command failure. Use -i to ignore errors.\n");
                    running = 0;
                }
            }
        }

        tv.tv_sec = 0;
        tv.tv_usec = POLL_INTERVAL_MS * 1000;
        
        first_scan = 0;
    }

    for (int i = 0; i < num_dirs; i++) {
        free(dirs[i].path);
    }
    for (int i = 0; i < num_patterns; i++) {
        free(patterns[i]);
    }
    free(patterns);
    hash_free(&files);
    
    fprintf(output_stream, "Watch terminated.\n");
    return 0;
}