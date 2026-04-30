#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <libpq-fe.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
      printf("only 1 argument allow, please provide uri\n");
      exit(1);
    }
    const char *conninfo = argv[1];
    char *errmsg = NULL;

    PQconninfoOption *options = PQconninfoParse(conninfo, &errmsg);
    if (!options) {
        printf("Parse failed: %s\n", errmsg);
        return 1;
    }

    for (PQconninfoOption *opt = options; opt->keyword != NULL; opt++) {
        char upper[128];
        size_t i = 0;
        for (; opt->keyword[i] != '\0' && i < sizeof(upper)-1; i++)
            upper[i] = toupper((unsigned char)opt->keyword[i]);
        upper[i] = '\0';

        printf("URI_%s=%s\n", upper, opt->val ? opt->val : "");
    }

    PQconninfoFree(options);
    return 0;
}
