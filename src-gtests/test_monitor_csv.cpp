/**
 * @file   test_monitor_csv.cpp
 * @brief  Unit tests for CSV column consistency in monitor_thread output.
 *
 * The monitor writes rows using a chain of conditional fprintf calls.
 * A miscount in any branch causes column misalignment in every downstream
 * analysis tool.  These tests replicate the exact fprintf sequences and
 * verify that every row has the same number of fields as the header.
 *
 * No live ptpd process is required — values are hard-coded constants.
 *
 * Sanitizers: ASAN, UBSAN.
 */

#include "test_helpers.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

/* Count comma-separated fields in a single CSV line (no quoting). */
static int csv_field_count(const std::string &line) {
    if (line.empty()) return 0;
    int n = 1;
    for (char c : line)
        if (c == ',') ++n;
    return n;
}

/* Split a CSV line into tokens (no quoting, empty tokens allowed). */
static std::vector<std::string> csv_split(const std::string &line) {
    std::vector<std::string> toks;
    std::string cur;
    for (char c : line) {
        if (c == ',') { toks.push_back(cur); cur.clear(); }
        else cur += c;
    }
    toks.push_back(cur);
    return toks;
}

/* Read all non-empty lines from a FILE* into a vector. */
static std::vector<std::string> read_lines(FILE *fp) {
    std::vector<std::string> lines;
    char buf[1024];
    rewind(fp);
    while (fgets(buf, sizeof(buf), fp)) {
        std::string s(buf);
        // Strip trailing newline
        while (!s.empty() && (s.back() == '\n' || s.back() == '\r'))
            s.pop_back();
        if (!s.empty())
            lines.push_back(s);
    }
    return lines;
}

/* ------------------------------------------------------------------ */
/* Helpers that replicate the exact fprintf logic from ptpd-app.c     */
/*                                                                     */
/* We test three compile-time configurations:                          */
/*   CONFIG_BASE      : no PTPD_STATISTICS, no PTPD_USE_SWCLOCK       */
/*   CONFIG_STATS     : PTPD_STATISTICS, no PTPD_USE_SWCLOCK          */
/*   CONFIG_SWCLOCK   : no PTPD_STATISTICS, PTPD_USE_SWCLOCK          */
/*   CONFIG_BOTH      : both flags                                     */
/*                                                                     */
/* Each write_header / write_row pair exactly mirrors ptpd-app.c.     */
/* ------------------------------------------------------------------ */

enum Config {
    CONFIG_BASE    = 0,
    CONFIG_STATS   = 1,
    CONFIG_SWCLOCK = 2,
    CONFIG_BOTH    = 3
};

static void write_header(FILE *fp, Config cfg) {
    fprintf(fp,
        "timestamp_iso,"
        "elapsed_s,"
        "ptp_active,"
        "ptpd_offset_input_ns,"
        "ptpd_servo_output_ppb,"
        "ptpd_observed_drift_ppb,"
        "ptpd_kP,"
        "ptpd_kI");
    if (cfg == CONFIG_STATS || cfg == CONFIG_BOTH) {
        fprintf(fp, ","
            "ptpd_drift_mean_ppb,"
            "ptpd_drift_std_ppb,"
            "ptpd_drift_median_ppb,"
            "ptpd_update_count");
    }
    if (cfg == CONFIG_SWCLOCK || cfg == CONFIG_BOTH) {
        fprintf(fp, ","
            "swclock_remaining_phase_ns,"
            "swclock_mean_te_ns,"
            "swclock_std_te_ns,"
            "swclock_max_te_ns,"
            "swclock_mtie_1s_ns,"
            "swclock_mtie_10s_ns,"
            "swclock_tdev_1s_ns");
    }
    fprintf(fp, "\n");
}

static void write_row_active_with_metrics(FILE *fp, Config cfg) {
    /* Mirrors the ptp_active=1, have_metrics=1 path */
    fprintf(fp, "2024-01-01T00:00:01.000000Z,1.000,1,100,123.456,99.000,0.700000,0.200000");
    if (cfg == CONFIG_STATS || cfg == CONFIG_BOTH)
        fprintf(fp, ",50.000,10.000,48.000,42");
    if (cfg == CONFIG_SWCLOCK || cfg == CONFIG_BOTH)
        fprintf(fp, ",500,12.300,4.500,30.100,8.000,25.000,3.200");
    fprintf(fp, "\n");
}

static void write_row_active_no_metrics(FILE *fp, Config cfg) {
    /* Mirrors the ptp_active=1, have_metrics=0 path (swclock only) */
    fprintf(fp, "2024-01-01T00:00:02.000000Z,2.000,1,100,123.456,99.000,0.700000,0.200000");
    if (cfg == CONFIG_STATS || cfg == CONFIG_BOTH)
        fprintf(fp, ",50.000,10.000,48.000,42");
    if (cfg == CONFIG_SWCLOCK || cfg == CONFIG_BOTH)
        /* This is the branch being tested — 6 empty metric cols */
        fprintf(fp, ",%lld,,,,,,", (long long)500);
    fprintf(fp, "\n");
}

static void write_row_inactive(FILE *fp, Config cfg) {
    /* Mirrors the ptp_active=0 path */
    fprintf(fp, "2024-01-01T00:00:03.000000Z,3.000,0,0,0.000,0.000,0.000000,0.000000");
    if (cfg == CONFIG_STATS || cfg == CONFIG_BOTH)
        fprintf(fp, ",0.000,0.000,0.000,0");
    if (cfg == CONFIG_SWCLOCK || cfg == CONFIG_BOTH)
        fprintf(fp, ",%lld,,,,,,", (long long)0);
    fprintf(fp, "\n");
}

/* ------------------------------------------------------------------ */
/* Generic checker: verifies all data rows have same field count as   */
/* the header row.                                                     */
/* ------------------------------------------------------------------ */
static void check_column_consistency(Config cfg, bool include_no_metrics) {
    TempFile tf;
    FILE *fp = tf.fp();
    ASSERT_NE(fp, nullptr);

    write_header(fp, cfg);
    write_row_active_with_metrics(fp, cfg);
    if (include_no_metrics)
        write_row_active_no_metrics(fp, cfg);
    write_row_inactive(fp, cfg);
    fflush(fp);

    auto lines = read_lines(fp);
    ASSERT_GE((int)lines.size(), 2) << "Expected at least header + 1 data row";

    int header_cols = csv_field_count(lines[0]);
    EXPECT_GT(header_cols, 0);

    for (size_t i = 1; i < lines.size(); ++i) {
        int row_cols = csv_field_count(lines[i]);
        EXPECT_EQ(row_cols, header_cols)
            << "Row " << i << " has " << row_cols
            << " fields but header has " << header_cols
            << "\n  header: " << lines[0]
            << "\n  row:    " << lines[i];
    }
}

/* ------------------------------------------------------------------ */
/* T1: BASE config (no stats, no swclock) — all 3 row types           */
/* ------------------------------------------------------------------ */
TEST(MonitorCSV, BaseConfig_ColumnConsistency) {
    check_column_consistency(CONFIG_BASE, false);
}

/* ------------------------------------------------------------------ */
/* T2: STATS config — active with stats, inactive zero stats          */
/* ------------------------------------------------------------------ */
TEST(MonitorCSV, StatsConfig_ColumnConsistency) {
    check_column_consistency(CONFIG_STATS, false);
}

/* ------------------------------------------------------------------ */
/* T3: SWCLOCK config — active+metrics, active+no-metrics, inactive   */
/* This is the critical test: the "no metrics" else branch             */
/* must emit 7 swclock columns (1 value + 6 empty) to match header.  */
/* ------------------------------------------------------------------ */
TEST(MonitorCSV, SwclockConfig_NoMetrics_ColumnConsistency) {
    check_column_consistency(CONFIG_SWCLOCK, true /* include no-metrics row */);
}

/* ------------------------------------------------------------------ */
/* T4: BOTH config — all four columns groups present                  */
/* ------------------------------------------------------------------ */
TEST(MonitorCSV, BothConfig_ColumnConsistency) {
    check_column_consistency(CONFIG_BOTH, true);
}

/* ------------------------------------------------------------------ */
/* T5: Verify exact no-metrics else branch column count               */
/* The else branch: fprintf(fp, ",%lld,,,,,,", remaining_phase_ns)    */
/* produces 7 additional fields (1 value + 6 empty after trailing ,) */
/* The header has 7 swclock columns.                                  */
/* ------------------------------------------------------------------ */
TEST(MonitorCSV, NoMetricsBranch_ExactCount) {
    TempFile tf;
    FILE *fp = tf.fp();
    ASSERT_NE(fp, nullptr);

    /* Write the swclock portion of the header */
    const char *swclock_header =
        "swclock_remaining_phase_ns,"
        "swclock_mean_te_ns,"
        "swclock_std_te_ns,"
        "swclock_max_te_ns,"
        "swclock_mtie_1s_ns,"
        "swclock_mtie_10s_ns,"
        "swclock_tdev_1s_ns\n";

    /* Write the matching else-branch data */
    char row[128];
    snprintf(row, sizeof(row), "%lld,,,,,,%c", (long long)12345, '\n');

    fprintf(fp, "%s", swclock_header);
    fprintf(fp, "%s", row);
    fflush(fp);

    auto lines = read_lines(fp);
    ASSERT_EQ((int)lines.size(), 2);

    int header_cols = csv_field_count(lines[0]);
    int row_cols    = csv_field_count(lines[1]);
    EXPECT_EQ(header_cols, 7) << "swclock header should have 7 columns";
    EXPECT_EQ(row_cols,    header_cols)
        << "no-metrics else branch should emit exactly " << header_cols << " columns";
}

/* ------------------------------------------------------------------ */
/* T6: ptp_active field is integer 0 or 1                             */
/* ------------------------------------------------------------------ */
TEST(MonitorCSV, PtpActiveField_IsIntegerOneOrZero) {
    TempFile tf;
    FILE *fp = tf.fp();
    ASSERT_NE(fp, nullptr);

    write_header(fp, CONFIG_BASE);
    write_row_active_with_metrics(fp, CONFIG_BASE);
    write_row_inactive(fp, CONFIG_BASE);
    fflush(fp);

    auto lines = read_lines(fp);
    ASSERT_EQ((int)lines.size(), 3) << "header + 2 data rows";

    /* ptp_active is field index 2 (0-based) */
    for (int i = 1; i <= 2; ++i) {
        auto toks = csv_split(lines[i]);
        ASSERT_GE((int)toks.size(), 3) << "row " << i << " too short";
        const std::string &val = toks[2];
        EXPECT_TRUE(val == "0" || val == "1")
            << "ptp_active in row " << i << " is '" << val << "' but must be 0 or 1";
    }
}
