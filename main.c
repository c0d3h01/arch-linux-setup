#include <stdio.h>

int main() {
    printf("Usage: system-cleanup [OPTION]\n"
    "Options:\n"
    "  --clean         Remove orphaned packages\n"
    "  --cache         Clean package cache\n"
    "  --journal       Clean system journal\n"
    "  --all          Perform all cleanup operations\n"
    "  --help         Display this help message\n");
    return 0;
}
