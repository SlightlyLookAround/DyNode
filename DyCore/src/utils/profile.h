#pragma once

#include <chrono>
#include <limits>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

struct ProfileData {
    std::string name;
    double total_duration = 0.0;
    long long call_count = 0;
    double min_duration = std::numeric_limits<double>::max();
    double max_duration = 0.0;
    double last_duration = 0.0;
    std::vector<double> all_durations;
    size_t next_duration_index = 0;
    static constexpr size_t MAX_DURATIONS = 10000;

    void record(double duration);
    double average_duration() const;
};

class Profiler;

class ScopedTimer {
   private:
    Profiler& profiler;
    std::string name;
    std::chrono::high_resolution_clock::time_point start_time;
    bool enabled;

   public:
    ScopedTimer(const std::string& name, Profiler& profiler_instance,
                bool is_enabled = true);
    ~ScopedTimer();
};

class Profiler {
   private:
    std::unordered_map<std::string, ProfileData> records;
    mutable std::mutex mtx;

    Profiler() = default;

   public:
    Profiler(const Profiler&) = delete;
    Profiler& operator=(const Profiler&) = delete;

    static Profiler& get() {
        static Profiler instance;
        return instance;
    }

    void record(const std::string& name, double duration);
    void reset();
    std::optional<double> get_last_duration_ms(const std::string& name) const;
    void generate_report(std::ostream& os, double lag_threshold_multiplier = 100.0) const;
};

#define PROFILE_SCOPE_CONDITIONAL(name, enabled) \
    ScopedTimer timer##__LINE__(name, Profiler::get(), enabled)

#define PROFILE_FUNCTION_CONDITIONAL(enabled) \
    PROFILE_SCOPE_CONDITIONAL(__FUNCTION__, enabled)

#define PROFILE_SCOPE(name) PROFILE_SCOPE_CONDITIONAL(name, true)
#define PROFILE_FUNCTION() PROFILE_FUNCTION_CONDITIONAL(true)
