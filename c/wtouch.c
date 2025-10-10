#if !defined(_WIN32)
#    define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>

#if defined(_WIN32)
#    include <io.h>
#    include <sys/utime.h>
#    define STAT_STRUCT struct _stat64
#    define STAT_FUNC _stat64
#    define UTIME_STRUCT struct __utimbuf64
#    define UTIME_FUNC _utime64
#else
#    include <fcntl.h>
#    include <sys/time.h>
#    include <unistd.h>
#    define STAT_STRUCT struct stat
#    define STAT_FUNC stat
#endif

static bool get_local_time(time_t value, struct tm *out) {
#if defined(_WIN32)
    return localtime_s(out, &value) == 0;
#else
    return localtime_r(&value, out) != NULL;
#endif
}

static time_t stat_atime(const STAT_STRUCT *info) {
#if defined(_WIN32)
    return info->st_atime;
#elif defined(__APPLE__)
    return info->st_atimespec.tv_sec;
#elif defined(__linux__)
    return info->st_atim.tv_sec;
#else
    return info->st_atime;
#endif
}

static time_t stat_mtime(const STAT_STRUCT *info) {
#if defined(_WIN32)
    return info->st_mtime;
#elif defined(__APPLE__)
    return info->st_mtimespec.tv_sec;
#elif defined(__linux__)
    return info->st_mtim.tv_sec;
#else
    return info->st_mtime;
#endif
}

struct options {
    bool touch_access;
    bool touch_modify;
    bool no_create;
    const char *date_string;
    const char *timestamp_string;
    const char *reference_path;
    int path_count;
    const char **paths;
};

static void print_usage(FILE *out) {
    fprintf(out,
            "Usage: wtouch [OPTION]... FILE...\n\n"
            "  -a                   Change the access time only\n"
            "  -m                   Change the modification time only\n"
            "  -c, --no-create      Do not create any files\n"
            "  -d STRING            Parse STRING as an explicit timestamp (YYYY-MM-DD[ HH:MM[:SS]])\n"
            "  -t STAMP             Parse STAMP in [[CC]YY]MMDDhhmm[.ss] format\n"
            "  -r FILE              Use FILE's access/modification times\n"
            "      --               Treat all following arguments as literal paths\n");
}

static bool parse_args(int argc, char **argv, struct options *out) {
    memset(out, 0, sizeof(*out));

    int i = 1;
    for (; i < argc; ++i) {
        const char *arg = argv[i];
        if (strcmp(arg, "--") == 0) {
            ++i;
            break;
        }
        if (arg[0] != '-') {
            break;
        }
        if (strcmp(arg, "-a") == 0) {
            out->touch_access = true;
        } else if (strcmp(arg, "-m") == 0) {
            out->touch_modify = true;
        } else if (strcmp(arg, "-c") == 0 || strcmp(arg, "--no-create") == 0) {
            out->no_create = true;
        } else if (strcmp(arg, "-d") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "wtouch: option '-d' requires an argument\n");
                return false;
            }
            out->date_string = argv[i];
        } else if (strcmp(arg, "-t") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "wtouch: option '-t' requires an argument\n");
                return false;
            }
            out->timestamp_string = argv[i];
        } else if (strcmp(arg, "-r") == 0) {
            if (++i >= argc) {
                fprintf(stderr, "wtouch: option '-r' requires an argument\n");
                return false;
            }
            out->reference_path = argv[i];
        } else if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
            print_usage(stdout);
            exit(0);
        } else {
            fprintf(stderr, "wtouch: unrecognised option '%s'\n", arg);
            return false;
        }
    }

    out->paths = (const char **)(argv + i);
    out->path_count = argc - i;

    if (out->path_count <= 0) {
        fprintf(stderr, "wtouch: missing file operand\n");
        return false;
    }

    return true;
}

static bool parse_iso_datetime(const char *value, struct tm *out) {
    int year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
    size_t len = strlen(value);

    if (len == 10) {
        if (sscanf(value, "%d-%d-%d", &year, &month, &day) != 3) {
            return false;
        }
    } else if (len == 16) {
        if (sscanf(value, "%d-%d-%d %d:%d", &year, &month, &day, &hour, &minute) != 5) {
            return false;
        }
    } else if (len == 19) {
        if (sscanf(value, "%d-%d-%d %d:%d:%d", &year, &month, &day, &hour, &minute, &second) != 6) {
            return false;
        }
    } else {
        return false;
    }

    memset(out, 0, sizeof(*out));
    out->tm_year = year - 1900;
    out->tm_mon = month - 1;
    out->tm_mday = day;
    out->tm_hour = hour;
    out->tm_min = minute;
    out->tm_sec = second;
    out->tm_isdst = -1;
    return true;
}

static bool parse_datetime(const char *value, time_t *out) {
    struct tm parsed;
    if (!parse_iso_datetime(value, &parsed)) {
        return false;
    }
    *out = mktime(&parsed);
    return true;
}

static bool parse_timestamp_format(const char *value, time_t *out) {
    size_t len = strlen(value);
    int seconds = 0;
    char main_part[32];

    if (len >= sizeof(main_part)) {
        return false;
    }

    const char *dot = strchr(value, '.');
    if (dot) {
        if (strlen(dot + 1) != 2 || dot[1] < '0' || dot[1] > '9' || dot[2] < '0' || dot[2] > '9') {
            return false;
        }
        seconds = (dot[1] - '0') * 10 + (dot[2] - '0');
        len = (size_t)(dot - value);
        memcpy(main_part, value, len);
        main_part[len] = '\0';
    } else {
        strcpy(main_part, value);
    }

    if (len != 8 && len != 10 && len != 12) {
        return false;
    }

    for (size_t i = 0; i < len; ++i) {
        if (main_part[i] < '0' || main_part[i] > '9') {
            return false;
        }
    }

    time_t now = time(NULL);
    struct tm now_tm;
    if (!get_local_time(now, &now_tm)) {
        return false;
    }

    int index = (int)len;
    int minute = 0;
    int hour = 0;
    int day = 0;
    int month = 0;

#define TAKE(component)                          \
    do {                                         \
        if (index < 2) {                         \
            return false;                        \
        }                                        \
        component = (main_part[index - 2] - '0') * 10 + (main_part[index - 1] - '0'); \
        index -= 2;                              \
    } while (0)

    TAKE(minute);
    TAKE(hour);
    TAKE(day);
    TAKE(month);

    int year = now_tm.tm_year + 1900;
    if (index == 2) {
        year = (year / 100) * 100 + (main_part[0] - '0') * 10 + (main_part[1] - '0');
    } else if (index == 4) {
        year = (main_part[0] - '0') * 1000 + (main_part[1] - '0') * 100 +
               (main_part[2] - '0') * 10 + (main_part[3] - '0');
    } else if (index != 0) {
        return false;
    }

#undef TAKE

    struct tm tm_value;
    memset(&tm_value, 0, sizeof(tm_value));
    tm_value.tm_year = year - 1900;
    tm_value.tm_mon = month - 1;
    tm_value.tm_mday = day;
    tm_value.tm_hour = hour;
    tm_value.tm_min = minute;
    tm_value.tm_sec = seconds;
    tm_value.tm_isdst = -1;

    *out = mktime(&tm_value);
    return true;
}

static bool load_reference(const char *path, time_t *atime, time_t *mtime) {
    STAT_STRUCT info;
    if (STAT_FUNC(path, &info) != 0) {
        return false;
    }
    *atime = stat_atime(&info);
    *mtime = stat_mtime(&info);
    return true;
}

static bool ensure_exists(const char *path) {
    STAT_STRUCT info;
    if (STAT_FUNC(path, &info) == 0) {
        return true;
    }
    FILE *file = fopen(path, "ab");
    if (!file) {
        return false;
    }
    fclose(file);
    return true;
}

static bool apply_times(const char *path, time_t atime, time_t mtime, bool touch_access, bool touch_modify) {
    STAT_STRUCT info;
    if (STAT_FUNC(path, &info) != 0) {
        return false;
    }

#if defined(_WIN32)
    UTIME_STRUCT times = {
        .actime = touch_access ? atime : stat_atime(&info),
        .modtime = touch_modify ? mtime : stat_mtime(&info),
    };
    return UTIME_FUNC(path, &times) == 0;
#else
    struct timeval values[2];
    values[0].tv_sec = touch_access ? atime : stat_atime(&info);
    values[0].tv_usec = 0;
    values[1].tv_sec = touch_modify ? mtime : stat_mtime(&info);
    values[1].tv_usec = 0;
    return utimes(path, values) == 0;
#endif
}

int main(int argc, char **argv) {
    struct options opts;
    if (!parse_args(argc, argv, &opts)) {
        print_usage(stderr);
        return 1;
    }

    bool update_access = opts.touch_access || (!opts.touch_access && !opts.touch_modify);
    bool update_modify = opts.touch_modify || (!opts.touch_access && !opts.touch_modify);

    int explicit_sources = 0;
    if (opts.reference_path) {
        ++explicit_sources;
    }
    if (opts.date_string) {
        ++explicit_sources;
    }
    if (opts.timestamp_string) {
        ++explicit_sources;
    }
    if (explicit_sources > 1) {
        fprintf(stderr, "wtouch: options -r, -d and -t are mutually exclusive\n");
        return 1;
    }

    time_t explicit_atime = 0;
    time_t explicit_mtime = 0;
    bool have_explicit_times = false;

    if (opts.reference_path) {
        if (!load_reference(opts.reference_path, &explicit_atime, &explicit_mtime)) {
            fprintf(stderr, "wtouch: failed to read reference '%s': %s\n", opts.reference_path, strerror(errno));
            return 1;
        }
        have_explicit_times = true;
    } else if (opts.date_string) {
        if (!parse_datetime(opts.date_string, &explicit_atime)) {
            fprintf(stderr, "wtouch: failed to parse date '%s'\n", opts.date_string);
            return 1;
        }
        explicit_mtime = explicit_atime;
        have_explicit_times = true;
    } else if (opts.timestamp_string) {
        if (!parse_timestamp_format(opts.timestamp_string, &explicit_atime)) {
            fprintf(stderr, "wtouch: failed to parse timestamp '%s'\n", opts.timestamp_string);
            return 1;
        }
        explicit_mtime = explicit_atime;
        have_explicit_times = true;
    }

    time_t now = time(NULL);

    for (int i = 0; i < opts.path_count; ++i) {
        const char *path = opts.paths[i];
        STAT_STRUCT info;
        if (STAT_FUNC(path, &info) != 0) {
            if (opts.no_create) {
                continue;
            }
            if (!ensure_exists(path)) {
                fprintf(stderr, "wtouch: failed to create '%s': %s\n", path, strerror(errno));
                return 1;
            }
        }

        time_t atime = now;
        time_t mtime = now;
        if (have_explicit_times) {
            atime = explicit_atime;
            mtime = explicit_mtime;
        }

        if (!apply_times(path, atime, mtime, update_access, update_modify)) {
            fprintf(stderr, "wtouch: failed to update '%s': %s\n", path, strerror(errno));
            return 1;
        }
    }

    return 0;
}
