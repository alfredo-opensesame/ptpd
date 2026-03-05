#pragma once
/**
 * @file   test_helpers.h
 * @brief  Shared test utilities for ptpd src-gtests.
 *
 * Keep this header-only (no .cpp) to avoid needing a separate compilation
 * unit in every test target's CMake rule.
 */

#include <gtest/gtest.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
#include <time.h>
#include <unistd.h>
}

/* ------------------------------------------------------------------ */
/* TempFile — RAII wrapper that creates a writable temp file           */
/* and removes it on destruction.                                      */
/* ------------------------------------------------------------------ */
class TempFile {
public:
    TempFile() {
        char tmpl[] = "/tmp/ptpd_test_XXXXXX";
        int fd = mkstemp(tmpl);
        if (fd < 0)
            throw std::runtime_error(std::string("mkstemp: ") + strerror(errno));
        /* Re-open as FILE* (r+w) so callers can write and read back */
        fp_ = fdopen(fd, "w+");
        if (!fp_) {
            close(fd);
            throw std::runtime_error(std::string("fdopen: ") + strerror(errno));
        }
        path_ = tmpl;
    }
    ~TempFile() {
        if (fp_) fclose(fp_);
        unlink(path_.c_str());
    }

    /* Non-copyable */
    TempFile(const TempFile &) = delete;
    TempFile &operator=(const TempFile &) = delete;

    const std::string &path() const { return path_; }

    /** Open FILE* for write+read (created on construction). */
    FILE *fp() const { return fp_; }

    /* Read all lines from the file into a vector */
    std::vector<std::string> lines() const {
        std::vector<std::string> result;
        FILE *f = fopen(path_.c_str(), "r");
        if (!f) return result;
        char buf[4096];
        while (fgets(buf, sizeof(buf), f)) {
            std::string s(buf);
            if (!s.empty() && s.back() == '\n')
                s.pop_back();
            result.push_back(std::move(s));
        }
        fclose(f);
        return result;
    }

    /* Count comma-separated fields in a line */
    static int field_count(const std::string &line) {
        int n = 1;
        for (char c : line)
            if (c == ',') ++n;
        return n;
    }

private:
    std::string path_;
    FILE       *fp_ = nullptr;
};

/* ------------------------------------------------------------------ */
/* elapsed_ms() — wall-clock milliseconds since a reference timespec  */
/* Uses CLOCK_MONOTONIC — immune to CLOCK_REALTIME steps.             */
/* ------------------------------------------------------------------ */
inline double elapsed_ms(const struct timespec &ref) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)(now.tv_sec  - ref.tv_sec)  * 1000.0
         + (double)(now.tv_nsec - ref.tv_nsec) / 1e6;
}

inline struct timespec mono_now() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts;
}
