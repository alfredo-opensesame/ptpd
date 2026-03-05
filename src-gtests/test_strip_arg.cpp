/**
 * @file   test_strip_arg.cpp
 * @brief  Unit tests for strip_arg() in ptpd_app_utils.c
 *
 * Sanitizers: ASAN (buffer overflow T8), UBSAN (argv shifting).
 */

#include "test_helpers.h"

extern "C" {
#include "ptpd_app_utils.h"
#include <limits.h>
}

#include <cstring>
#include <string>
#include <vector>

/* Build a mutable argv array from a vector of strings.
 * We need char* (not const char*) to match the real argv signature. */
static std::vector<char *> make_argv(std::vector<std::string> &strs) {
    std::vector<char *> argv;
    for (auto &s : strs)
        argv.push_back(const_cast<char *>(s.c_str()));
    argv.push_back(nullptr); /* sentinel, not counted in argc */
    return argv;
}

/* ------------------------------------------------------------------ */
/* T1: Strip a no-value flag                                          */
/* ------------------------------------------------------------------ */
TEST(StripArg, NoValueFlag_Stripped) {
    std::vector<std::string> strs = {"ptpd-app", "--show-time", "-c", "foo.conf"};
    auto argv = make_argv(strs);
    int argc = 4;

    int rc = strip_arg(&argc, argv.data(), 1, "--show-time", 0, nullptr, 0);

    EXPECT_EQ(rc, 1);
    EXPECT_EQ(argc, 3);
    EXPECT_STREQ(argv[1], "-c");
    EXPECT_STREQ(argv[2], "foo.conf");
}

/* ------------------------------------------------------------------ */
/* T2: Strip a flag that takes a value                                */
/* ------------------------------------------------------------------ */
TEST(StripArg, ValueFlag_Stripped) {
    std::vector<std::string> strs = {"ptpd-app", "--servo-log", "/tmp/x.csv", "-c", "f.conf"};
    auto argv = make_argv(strs);
    int argc = 5;
    char buf[PATH_MAX] = {};

    int rc = strip_arg(&argc, argv.data(), 1, "--servo-log", 1, buf, sizeof(buf));

    EXPECT_EQ(rc, 1);
    EXPECT_EQ(argc, 3);
    EXPECT_STREQ(buf, "/tmp/x.csv");
    EXPECT_STREQ(argv[1], "-c");
    EXPECT_STREQ(argv[2], "f.conf");
}

/* ------------------------------------------------------------------ */
/* T3: Flag not present — no modification                             */
/* ------------------------------------------------------------------ */
TEST(StripArg, FlagAbsent_NoChange) {
    std::vector<std::string> strs = {"ptpd-app", "-c", "foo.conf"};
    auto argv = make_argv(strs);
    int argc = 3;

    int rc = strip_arg(&argc, argv.data(), 1, "--servo-log", 1, nullptr, 0);

    EXPECT_EQ(rc, 0);
    EXPECT_EQ(argc, 3);
    EXPECT_STREQ(argv[1], "-c");
}

/* ------------------------------------------------------------------ */
/* T4: Custom flags interleaved with ptpd flags — only custom removed */
/* ------------------------------------------------------------------ */
TEST(StripArg, Interleaved_OnlyCustomRemoved) {
    std::vector<std::string> strs = {
        "ptpd-app", "-i", "en5", "--servo-log", "/tmp/s.csv", "-f", "p.log"
    };
    auto argv = make_argv(strs);
    int argc = 7;
    char buf[PATH_MAX] = {};

    /* Strip --servo-log at index 3 */
    int rc = strip_arg(&argc, argv.data(), 3, "--servo-log", 1, buf, sizeof(buf));

    EXPECT_EQ(rc, 1);
    EXPECT_EQ(argc, 5);
    EXPECT_STREQ(buf, "/tmp/s.csv");
    /* ptpd flags preserved */
    EXPECT_STREQ(argv[1], "-i");
    EXPECT_STREQ(argv[2], "en5");
    EXPECT_STREQ(argv[3], "-f");
    EXPECT_STREQ(argv[4], "p.log");
}

/* ------------------------------------------------------------------ */
/* T5: Two sequential custom flags both stripped                      */
/* ------------------------------------------------------------------ */
TEST(StripArg, TwoCustomFlags_BothStripped) {
    std::vector<std::string> strs = {
        "ptpd-app", "--show-time", "--pidfile", "/tmp/p.pid", "-c", "f.conf"
    };
    auto argv = make_argv(strs);
    int argc = 6;
    char pid_buf[PATH_MAX] = {};

    /* Strip --show-time first (index 1, no value) */
    int rc1 = strip_arg(&argc, argv.data(), 1, "--show-time", 0, nullptr, 0);
    /* argv is now: ptpd-app --pidfile /tmp/p.pid -c f.conf  argc=5 */

    /* Strip --pidfile (now at index 1) */
    int rc2 = strip_arg(&argc, argv.data(), 1, "--pidfile", 1, pid_buf, sizeof(pid_buf));

    EXPECT_EQ(rc1, 1);
    EXPECT_EQ(rc2, 1);
    EXPECT_EQ(argc, 3);
    EXPECT_STREQ(pid_buf, "/tmp/p.pid");
    EXPECT_STREQ(argv[1], "-c");
    EXPECT_STREQ(argv[2], "f.conf");
}

/* ------------------------------------------------------------------ */
/* T6: Flag at last valid position (value is the last element)        */
/* ------------------------------------------------------------------ */
TEST(StripArg, FlagValueAtEnd) {
    std::vector<std::string> strs = {"ptpd-app", "--servo-log", "/tmp/end.csv"};
    auto argv = make_argv(strs);
    int argc = 3;
    char buf[PATH_MAX] = {};

    int rc = strip_arg(&argc, argv.data(), 1, "--servo-log", 1, buf, sizeof(buf));

    EXPECT_EQ(rc, 1);
    EXPECT_EQ(argc, 1);
    EXPECT_STREQ(buf, "/tmp/end.csv");
}

/* ------------------------------------------------------------------ */
/* T7: Duplicate flag — first occurrence wins, second left in argv    */
/* ------------------------------------------------------------------ */
TEST(StripArg, DuplicateFlag_FirstWins) {
    std::vector<std::string> strs = {
        "ptpd-app", "--servo-log", "/tmp/first.csv", "--servo-log", "/tmp/second.csv"
    };
    auto argv = make_argv(strs);
    int argc = 5;
    char buf[PATH_MAX] = {};

    /* Caller loop would strip index 1 first */
    int rc = strip_arg(&argc, argv.data(), 1, "--servo-log", 1, buf, sizeof(buf));

    EXPECT_EQ(rc, 1);
    EXPECT_STREQ(buf, "/tmp/first.csv");
    /* Second occurrence still present for the caller's next loop iteration */
    EXPECT_EQ(argc, 3);
    EXPECT_STREQ(argv[1], "--servo-log");
    EXPECT_STREQ(argv[2], "/tmp/second.csv");
}

/* ------------------------------------------------------------------ */
/* T8: Buffer truncation — value longer than buf_len is truncated     */
/* (ASAN verifies no write past the buffer end)                       */
/* ------------------------------------------------------------------ */
TEST(StripArg, ValueTruncatedToBufferLen) {
    std::string long_path(PATH_MAX + 10, 'x');
    std::vector<std::string> strs = {"ptpd-app", "--servo-log", long_path};
    auto argv = make_argv(strs);
    int argc = 3;
    char buf[8] = {};

    strip_arg(&argc, argv.data(), 1, "--servo-log", 1, buf, sizeof(buf));

    /* Must be NUL-terminated and at most 7 chars */
    EXPECT_EQ(strnlen(buf, sizeof(buf)), (size_t)7);
    EXPECT_EQ(buf[7], '\0');
}
