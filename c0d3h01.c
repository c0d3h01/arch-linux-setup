#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

// Function prototypes
int cleanup_orphans(void);
int cleanup_package_cache(void);
int cleanup_journal(void);
void print_usage(void);

// Main cleanup function for orphaned packages
int cleanup_orphans(void) {
    printf("Cleaning up orphaned packages...\n");

    // Get list of orphaned packages
    FILE *cmd = popen("pacman -Qtdq", "r");
    if (cmd == NULL) {
        perror("Failed to execute pacman -Qtdq");
        return 1;
    }

    // Read the output and build the removal command
    char packages[4096] = "";
    char line[256];
    while (fgets(line, sizeof(line), cmd)) {
        strcat(packages, line);
    }
    pclose(cmd);

    // If there are orphaned packages, remove them
    if (strlen(packages) > 0) {
        char command[4096];
        snprintf(command, sizeof(command),
                "sudo pacman -Rns %s --noconfirm", packages);

        int status = system(command);
        if (status != 0) {
            fprintf(stderr, "Failed to remove orphaned packages\n");
            return 1;
        }
        printf("Orphaned packages removed successfully\n");
    } else {
        printf("No orphaned packages found\n");
    }

    return 0;
}

// Clean package cache
int cleanup_package_cache(void) {
    printf("Cleaning package cache...\n");
    int status = system("sudo paccache -rk1");  // Keep only one version
    if (status != 0) {
        fprintf(stderr, "Failed to clean package cache\n");
        return 1;
    }
    printf("Package cache cleaned successfully\n");
    return 0;
}

// Clean systemd journal
int cleanup_journal(void) {
    printf("Cleaning system journal...\n");
    int status = system("sudo journalctl --vacuum-size=100M");
    if (status != 0) {
        fprintf(stderr, "Failed to clean system journal\n");
        return 1;
    }
    printf("System journal cleaned successfully\n");
    return 0;
}

void print_usage(void) {
    printf("Usage: system-cleanup [OPTION]\n");
    printf("Options:\n");
    printf("  --clean         Remove orphaned packages\n");
    printf("  --cache         Clean package cache\n");
    printf("  --journal       Clean system journal\n");
    printf("  --all          Perform all cleanup operations\n");
    printf("  --help         Display this help message\n");
}

int main(int argc, char *argv[]) {
    // Check if running as root
    if (geteuid() != 0) {
        fprintf(stderr, "This program must be run as root\n");
        return 1;
    }

    // Check arguments
    if (argc < 2) {
        print_usage();
        return 1;
    }

    // Process command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--clean") == 0) {
            if (cleanup_orphans() != 0) return 1;
        }
        else if (strcmp(argv[i], "--cache") == 0) {
            if (cleanup_package_cache() != 0) return 1;
        }
        else if (strcmp(argv[i], "--journal") == 0) {
            if (cleanup_journal() != 0) return 1;
        }
        else if (strcmp(argv[i], "--all") == 0) {
            if (cleanup_orphans() != 0) return 1;
            if (cleanup_package_cache() != 0) return 1;
            if (cleanup_journal() != 0) return 1;
        }
        else if (strcmp(argv[i], "--help") == 0) {
            print_usage();
            return 0;
        }
        else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage();
            return 1;
        }
    }

    return 0;
}
