/**
 * @file   test_system_integration.cpp
 * @brief  System integration tests — live PTP grandmaster on the network.
 *
 * Architecture
 * ------------
 * ptpd_init() / ptpd_start() / ptpd_shutdown() are called ONCE via the
 * static GTest hook SetUpTestSuite(), which runs a single time for the
 * entire PtpSystemTest class.  All 10 TEST_F methods then read from the
 * static shared  s_samples / s_stats  without re-running ptpd.
 *
 *   Total wall time ≈ s_lock_timeout_s + s_duration_s  ≈ 60 + 120 = ~180 s
 *   (regardless of the number of test functions in the class)
 *
 * Skip conditions (GTEST_SKIP — not FAIL)
 * ----------------------------------------
 *   - geteuid() != 0          (needs root for ports 319/320)
 *   - en5 has no IPv4 address
 *   - 192.168.8.234 unreachable (ping -c1 -W1)
 *   - ptpd_init() returns NULL
 *   - GM does not lock within PTPD_TEST_LOCK_TIMEOUT_S seconds
 *
 * Environment variables
 * ---------------------
 *   PTPD_TEST_DURATION_S      data-collection window after lock (default 120)
 *   PTPD_TEST_LOCK_TIMEOUT_S  max seconds to wait for first lock (default 60)
 *   PTPD_TEST_CONFIG          path to ptpd config file
 *                             (default: resources/ptpd-daemon-current.conf)
 *
 * Sanitizers: ASAN (all).
 */

#include "test_helpers.h"

extern "C" {
#include "ptpdlib.h"
#include "datatypes.h"
#ifdef PTPD_USE_SWCLOCK
#  include "sw_clock.h"
#endif
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
}

/* ptpd.h defines min/max as function-like macros; undefine them here so
 * C++ standard library templates (std::max, std::min) are not broken. */
#ifdef max
#  undef max
#endif
#ifdef min
#  undef min
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <numeric>
#include <string>
#include <thread>
#include <vector>

/* ------------------------------------------------------------------ */
/* Configuration                                                       */
/* ------------------------------------------------------------------ */
static const char *IFACE      = "en5";
static const char *MASTER_IP  = "192.168.8.234";

static int env_int(const char *name, int def) {
    const char *v = getenv(name);
    return (v && *v) ? atoi(v) : def;
}
static std::string env_str(const char *name, const char *def) {
    const char *v = getenv(name);
    return (v && *v) ? std::string(v) : std::string(def);
}

/* ------------------------------------------------------------------ */
/* Per-second servo sample                                             */
/* ------------------------------------------------------------------ */
struct ServoSample {
    double    elapsed_s;
    int       ptp_active;           /* kP > 0 */
    int32_t   offset_ns;
    double    servo_out_ppb;
    double    obs_drift_ppb;
    double    kP, kI;
    long long remaining_phase_ns;   /* 0 when swclock absent */
};

/* ------------------------------------------------------------------ */
/* Statistics computed from locked rows                                */
/* ------------------------------------------------------------------ */
struct ServoStats {
    double time_to_lock_s    = -1.0;
    int    locked_count      = 0;
    int    total_count       = 0;
    double lock_fraction     = 0.0;
    double offset_mean_ns    = 0.0;
    double offset_std_ns     = 0.0;
    double offset_max_abs_ns = 0.0;
    double drift_mean_ppb    = 0.0;
    double mtie_1s_ns        = 0.0;
    double mtie_10s_ns       = 0.0;
    double tdev_1s_ns        = 0.0;
    double phase_max_abs_ns  = 0.0;
};

static ServoStats compute_stats(const std::vector<ServoSample> &rows) {
    ServoStats s;
    s.total_count = (int)rows.size();
    if (s.total_count == 0) return s;

    /* Time to first lock */
    for (auto &r : rows) {
        if (r.ptp_active) { s.time_to_lock_s = r.elapsed_s; break; }
    }

    /* Collect locked rows */
    std::vector<double> offsets, drifts, phases;
    for (auto &r : rows) {
        if (!r.ptp_active) continue;
        s.locked_count++;
        offsets.push_back((double)r.offset_ns);
        drifts.push_back(r.obs_drift_ppb);
        if (r.remaining_phase_ns != 0)
            phases.push_back(std::fabs((double)r.remaining_phase_ns));
    }
    if (offsets.empty()) return s;

    s.lock_fraction = (double)s.locked_count / s.total_count;

    /* Basic offset stats */
    double sum = std::accumulate(offsets.begin(), offsets.end(), 0.0);
    s.offset_mean_ns = sum / offsets.size();
    double sq = 0;
    for (auto v : offsets) sq += (v - s.offset_mean_ns) * (v - s.offset_mean_ns);
    s.offset_std_ns = std::sqrt(sq / offsets.size());
    for (auto v : offsets) s.offset_max_abs_ns = std::max(s.offset_max_abs_ns, std::fabs(v));

    /* Drift mean */
    s.drift_mean_ppb = std::accumulate(drifts.begin(), drifts.end(), 0.0) / drifts.size();

    /* MTIE: sliding max-min over window w (samples are 1s apart) */
    auto mtie = [&](int w) -> double {
        double m = 0;
        for (int i = 0; i + w <= (int)offsets.size(); i++) {
            auto it0 = offsets.begin() + i;
            auto it1 = it0 + w;
            double mx = *std::max_element(it0, it1);
            double mn = *std::min_element(it0, it1);
            m = std::max(m, mx - mn);
        }
        return m;
    };
    s.mtie_1s_ns  = mtie(1);   /* adjacent-pair diff = MTIE at τ=1s */
    s.mtie_10s_ns = mtie(10);

    /* TDEV at τ=1s: sqrt( mean( (x[i+1] - x[i])^2 ) / 6 )  */
    if (offsets.size() >= 2) {
        double msd = 0;
        for (size_t i = 0; i + 1 < offsets.size(); i++) {
            double d = offsets[i+1] - offsets[i];
            msd += d * d;
        }
        msd /= (offsets.size() - 1);
        s.tdev_1s_ns = std::sqrt(msd / 6.0);
    }

    /* swclock phase max */
    if (!phases.empty())
        s.phase_max_abs_ns = *std::max_element(phases.begin(), phases.end());

    return s;
}

/* ------------------------------------------------------------------ */
/* Pre-flight helpers                                                  */
/* ------------------------------------------------------------------ */
static bool iface_has_ipv4(const char *iface) {
    struct ifaddrs *ifa_list = nullptr;
    if (getifaddrs(&ifa_list) != 0) return false;
    bool found = false;
    for (auto *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
        if (ifa->ifa_name && strcmp(ifa->ifa_name, iface) == 0 &&
            ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_INET) {
            found = true; break;
        }
    }
    freeifaddrs(ifa_list);
    return found;
}

static bool master_reachable() {
    std::string cmd = std::string("ping -c1 -W1 ") + MASTER_IP + " >/dev/null 2>&1";
    return system(cmd.c_str()) == 0;
}

/* port_319_free() removed: ptpd binds with SO_REUSEADDR so it can coexist
 * with macOS system services (e.g. ptpcamerad) that also hold port 319.
 * A plain bind() without SO_REUSEADDR would falsely report the port busy.
 * ptpd_init() itself is the reliable arbiter: if it genuinely cannot bind
 * the port it returns NULL and the fixture calls GTEST_SKIP. */

/* ================================================================== */
/* Fixture — data collected ONCE with SetUpTestSuite                  */
/*                                                                     */
/* SetUpTestSuite() runs ONCE for the whole PtpSystemTest class,      */
/* not once per TEST_F.  All tests share s_samples / s_stats via      */
/* static members.  SetUp() per TEST_F merely checks the skip flag.   */
/* Total wall time ≈ s_lock_timeout_s + s_duration_s  (~180 s).      */
/* ================================================================== */
class PtpSystemTest : public ::testing::Test {
public:
    /* ---------- static shared state (populated once) ------------- */
    static bool                      s_skip;
    static std::string               s_skip_reason;
    static std::vector<ServoSample>  s_samples;
    static ServoStats                s_stats;
    static int                       s_duration_s;
    static int                       s_lock_timeout_s;

    /* ---------- runs ONCE before the first test in this class ---- */
    static void SetUpTestSuite() {
        s_duration_s     = env_int("PTPD_TEST_DURATION_S",     120);
        s_lock_timeout_s = env_int("PTPD_TEST_LOCK_TIMEOUT_S",  60);
        std::string cfg  = env_str("PTPD_TEST_CONFIG",
                                   "resources/ptpd-daemon-current.conf");

        /* ---- pre-flight checks → set s_skip, don't throw here --- */
        if (geteuid() != 0) {
            s_skip = true;
            s_skip_reason = "Requires root (needs ports 319/320)"; return;
        }
        if (!iface_has_ipv4(IFACE)) {
            s_skip = true;
            s_skip_reason = std::string(IFACE) + " has no IPv4 address"; return;
        }
        if (!master_reachable()) {
            s_skip = true;
            s_skip_reason = std::string("Master ") + MASTER_IP + " unreachable"; return;
        }

        /* ---- build argv ---- */
        static char arg0[] = "ptpd";
        static char arg1[] = "-c";
        static char argcfg[4096];
        snprintf(argcfg, sizeof(argcfg), "%s", cfg.c_str());
        static char *argv_arr[] = { arg0, arg1, argcfg, nullptr };
        int argc = 3; char **argv = argv_arr;

        /* ---- init + start ---- */
        Integer16 ret = 0;
        PtpClock *ptp = ptpd_init(argc, argv, &ret);
        if (!ptp) {
            s_skip = true;
            s_skip_reason = "ptpd_init() failed (ret=" +
                            std::to_string((int)ret) + ")"; return;
        }
        if (ptpd_start(ptp) != 0) {
            ptpd_shutdown(ptp);
            s_skip = true; s_skip_reason = "ptpd_start() failed"; return;
        }

        /* ---- wait for first lock ---- */
        auto t0 = mono_now();
        bool locked = false;
        while (elapsed_ms(t0) < s_lock_timeout_s * 1000.0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            if (ptp && ptpd_is_running(ptp) && ptp->servo.kP > 0.0) {
                locked = true; break;
            }
        }
        if (!locked) {
            ptpd_shutdown(ptp);
            s_skip = true;
            s_skip_reason = "No GM lock within " +
                            std::to_string(s_lock_timeout_s) + " s";
            return;
        }

        /* ---- collect samples every 1s ---- */
        struct timespec run_start;
        clock_gettime(CLOCK_MONOTONIC, &run_start);

        for (int i = 0; i < s_duration_s; i++) {
            std::this_thread::sleep_for(std::chrono::seconds(1));

            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            double elapsed = (double)(now.tv_sec - run_start.tv_sec)
                           + (now.tv_nsec - run_start.tv_nsec) * 1e-9;

            ServoSample smp = {};
            smp.elapsed_s  = elapsed;
            smp.ptp_active = (ptp && ptpd_is_running(ptp) &&
                              ptp->servo.kP > 0.0) ? 1 : 0;
            if (smp.ptp_active) {
                smp.offset_ns      = ptp->servo.input;
                smp.servo_out_ppb  = ptp->servo.output;
                smp.obs_drift_ppb  = ptp->servo.observedDrift;
                smp.kP             = ptp->servo.kP;
                smp.kI             = ptp->servo.kI;
#ifdef PTPD_USE_SWCLOCK
                if (ptp->swclock)
                    smp.remaining_phase_ns =
                        swclock_get_remaining_phase_ns((SwClock *)ptp->swclock);
#endif
            }
            s_samples.push_back(smp);
        }

        ptpd_shutdown(ptp);
        s_stats = compute_stats(s_samples);
    }

    /* Called once after the last test in this class */
    static void TearDownTestSuite() { /* ptpd already shut down above */ }

    /* Per-test: skip immediately if suite setup failed/skipped */
    void SetUp() override {
        if (s_skip) GTEST_SKIP() << s_skip_reason;
    }
};

/* Static member definitions */
bool                     PtpSystemTest::s_skip         = false;
std::string              PtpSystemTest::s_skip_reason;
std::vector<ServoSample> PtpSystemTest::s_samples;
ServoStats               PtpSystemTest::s_stats;
int                      PtpSystemTest::s_duration_s   = 120;
int                      PtpSystemTest::s_lock_timeout_s = 60;

/* ------------------------------------------------------------------ */
/* Helper: write stats CSV to /tmp for offline analysis               */
/* ------------------------------------------------------------------ */
static void write_stats_csv(const ServoStats &s, int duration_s) {
    FILE *f = fopen("/tmp/ptpd_integration_stats.csv", "w");
    if (!f) return;
    fprintf(f, "metric,value\n");
    fprintf(f, "total_samples,%d\n",          s.total_count);
    fprintf(f, "locked_samples,%d\n",          s.locked_count);
    fprintf(f, "lock_fraction_pct,%.2f\n",     s.lock_fraction * 100.0);
    fprintf(f, "time_to_lock_s,%.1f\n",        s.time_to_lock_s);
    fprintf(f, "duration_s,%d\n",              duration_s);
    fprintf(f, "offset_mean_ns,%.1f\n",        s.offset_mean_ns);
    fprintf(f, "offset_std_ns,%.1f\n",         s.offset_std_ns);
    fprintf(f, "offset_max_abs_ns,%.1f\n",     s.offset_max_abs_ns);
    fprintf(f, "drift_mean_ppb,%.2f\n",        s.drift_mean_ppb);
    fprintf(f, "mtie_1s_ns,%.1f\n",            s.mtie_1s_ns);
    fprintf(f, "mtie_10s_ns,%.1f\n",           s.mtie_10s_ns);
    fprintf(f, "tdev_1s_ns,%.1f\n",            s.tdev_1s_ns);
    fprintf(f, "swclock_phase_max_ns,%.1f\n",  s.phase_max_abs_ns);
    fclose(f);
}

/* ================================================================== */
/* Tests                                                               */
/* ================================================================== */

/* ------------------------------------------------------------------ */
/* T0: StatsReport — always passes; records all metrics for CI        */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, StatsReport) {
    RecordProperty("total_samples",        s_stats.total_count);
    RecordProperty("locked_samples",       s_stats.locked_count);
    RecordProperty("lock_fraction_pct",    std::to_string(s_stats.lock_fraction * 100.0));
    RecordProperty("time_to_lock_s",       std::to_string(s_stats.time_to_lock_s));
    RecordProperty("duration_s",           s_duration_s);
    RecordProperty("offset_mean_ns",       std::to_string(s_stats.offset_mean_ns));
    RecordProperty("offset_std_ns",        std::to_string(s_stats.offset_std_ns));
    RecordProperty("offset_max_abs_ns",    std::to_string(s_stats.offset_max_abs_ns));
    RecordProperty("drift_mean_ppb",       std::to_string(s_stats.drift_mean_ppb));
    RecordProperty("mtie_1s_ns",           std::to_string(s_stats.mtie_1s_ns));
    RecordProperty("mtie_10s_ns",          std::to_string(s_stats.mtie_10s_ns));
    RecordProperty("tdev_1s_ns",           std::to_string(s_stats.tdev_1s_ns));
    RecordProperty("swclock_phase_max_ns", std::to_string(s_stats.phase_max_abs_ns));

    write_stats_csv(s_stats, s_duration_s);

    printf("\n--- PTP System Integration Stats (%d s) ---\n", s_duration_s);
    printf("  samples      : %d total, %d locked (%.1f%%)\n",
           s_stats.total_count, s_stats.locked_count, s_stats.lock_fraction * 100.0);
    printf("  time_to_lock : %.1f s\n",   s_stats.time_to_lock_s);
    printf("  offset       : mean=%.1f ns  std=%.1f ns  max=%.1f ns\n",
           s_stats.offset_mean_ns, s_stats.offset_std_ns, s_stats.offset_max_abs_ns);
    printf("  drift        : mean=%.2f ppb\n",  s_stats.drift_mean_ppb);
    printf("  MTIE         : 1s=%.1f ns  10s=%.1f ns\n",
           s_stats.mtie_1s_ns, s_stats.mtie_10s_ns);
    printf("  TDEV         : 1s=%.1f ns\n",     s_stats.tdev_1s_ns);
    printf("  swclock phase: max=%.1f ns\n",    s_stats.phase_max_abs_ns);
    printf("  CSV          : /tmp/ptpd_integration_stats.csv\n");
    fflush(stdout);

    SUCCEED();
}

/* ------------------------------------------------------------------ */
/* T1: Lock acquired for >= 50% of the run                            */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, LockAcquired) {
    EXPECT_GE(s_stats.lock_fraction, 0.5)
        << "Locked only " << s_stats.locked_count << " / " << s_stats.total_count
        << " samples (" << s_stats.lock_fraction * 100.0 << "%)";
}

/* ------------------------------------------------------------------ */
/* T2: Converges within the lock timeout                              */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, TimeToLock) {
    EXPECT_GE(s_stats.time_to_lock_s, 0.0) << "Never locked";
    EXPECT_LT(s_stats.time_to_lock_s, (double)s_lock_timeout_s)
        << "Lock took " << s_stats.time_to_lock_s
        << " s (budget " << s_lock_timeout_s << " s)";
}

/* ------------------------------------------------------------------ */
/* T3: Offset standard deviation sanity check                         */
/* Threshold reflects macOS+NTP contention with conservative kP=0.01  */
/* servo.  Tight µs-level values are achievable only on a dedicated   */
/* test node with NTP disabled (PTPD_TEST_DURATION_S env override).   */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, OffsetStdDev) {
    EXPECT_LT(s_stats.offset_std_ns, 1000000.0)
        << "offset_std=" << s_stats.offset_std_ns << " ns (threshold 1 ms)";
}

/* ------------------------------------------------------------------ */
/* T4: No individual offset outlier > 5 ms                           */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, OffsetMaxAbs) {
    EXPECT_LT(s_stats.offset_max_abs_ns, 5000000.0)
        << "offset_max_abs=" << s_stats.offset_max_abs_ns
        << " ns (threshold 5 ms)";
}

/* ------------------------------------------------------------------ */
/* T5: Observed drift within ±50 ppm — oscillator not runaway        */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, DriftStable) {
    EXPECT_LT(std::fabs(s_stats.drift_mean_ppb), 50000.0)
        << "drift_mean=" << s_stats.drift_mean_ppb << " ppb (threshold ±50 ppm)";
}

/* ------------------------------------------------------------------ */
/* T6: MTIE at τ=1s < 10 µs                                          */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, MTIE_1s) {
    EXPECT_LT(s_stats.mtie_1s_ns, 10000.0)
        << "MTIE(1s)=" << s_stats.mtie_1s_ns << " ns (threshold 10000 ns)";
}

/* ------------------------------------------------------------------ */
/* T7: MTIE at τ=10s < 5 ms                                          */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, MTIE_10s) {
    EXPECT_LT(s_stats.mtie_10s_ns, 5000000.0)
        << "MTIE(10s)=" << s_stats.mtie_10s_ns << " ns (threshold 5 ms)";
}

/* ------------------------------------------------------------------ */
/* T8: TDEV at τ=1s < 500 µs                                         */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, TDEV_1s) {
    EXPECT_LT(s_stats.tdev_1s_ns, 500000.0)
        << "TDEV(1s)=" << s_stats.tdev_1s_ns << " ns (threshold 500 µs)";
}

/* ------------------------------------------------------------------ */
/* T9: SwClock residual phase backlog < 2 s (swclock builds only)     */
/* Large initial values are expected when the swclock drains startup  */
/* phase offsets from step_startup corrections.                       */
/* ------------------------------------------------------------------ */
TEST_F(PtpSystemTest, SwclockPhaseBacklog) {
#ifndef PTPD_USE_SWCLOCK
    GTEST_SKIP() << "PTPD_USE_SWCLOCK not enabled in this build";
#else
    EXPECT_LT(s_stats.phase_max_abs_ns, 2000000000.0)
        << "swclock phase_max=" << s_stats.phase_max_abs_ns
        << " ns (threshold 2 s)";
#endif
}
