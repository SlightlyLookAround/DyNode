#include <exception>
#include <random>
#include <regex>
#include <taskflow/algorithm/sort.hpp>

#include "api.h"
#include "gm.h"
#include "notePoolManager.h"
#include "utils.h"
// Copies a block of memory from a source address to a destination address.
DYCORE_API double DyCore_buffer_copy(void* dst, void* src, double size) {
    memcpy(dst, src, (size_t)size);
    return 0;
}

// Parallel index sort threshold. Below this, task scheduling overhead
// outweighs the parallel merge sort.
inline constexpr size_t INDEX_SORT_PARALLEL_THRESHOLD = 4096;

// Sorts an array of std::pair<double, double> in ascending order based on the
// first element of the pair.
DYCORE_API double DyCore_index_sort(void* data, double size) {
    auto* pair_data = static_cast<std::pair<double, double>*>(data);
    const size_t count = static_cast<size_t>(size);
    if (count >= INDEX_SORT_PARALLEL_THRESHOLD) {
        tf::Taskflow taskflow;
        taskflow.sort(pair_data, pair_data + count);
        get_shared_taskflow_executor().run(taskflow).wait();
    } else {
        std::sort(pair_data, pair_data + count);
    }
    return 0;
}

// Sorts an array of doubles.
// The sorting order is determined by the 'type' parameter.
//
// @param data A pointer to the array of doubles.
// @param size The number of elements in the array.
// @param type If true, sorts in ascending order; otherwise, sorts in descending
// order.
DYCORE_API double DyCore_quick_sort(void* data, double size, double type) {
    double* arr = static_cast<double*>(data);
    if (type) {
        std::sort(arr, arr + (size_t)size);
    } else {
        std::sort(arr, arr + (size_t)size, std::greater<double>());
    }
    return 0;
}

DYCORE_API const char* DyCore_random_string(double length) {
    static std::string str;
    str = random_string(int(length));
    return str.c_str();
}

static std::mt19937_64 mt19937(
    std::chrono::high_resolution_clock::now().time_since_epoch().count());

DYCORE_API double DyCore_random_range(double min, double max) {
    if (min > max) {
        throw_error_event("Invalid range");
        return min;
    }
    std::uniform_real_distribution<double> dist(min, max);
    return dist(mt19937);
}

DYCORE_API double DyCore_irandom_range(double min, double max) {
    if (min > max) {
        throw_error_event("Invalid range");
        return min;
    }
    std::uniform_int_distribution<int64_t> dist(static_cast<int64_t>(min),
                                                static_cast<int64_t>(max));
    return dist(mt19937);
}

DYCORE_API double DyCore_regex_match(const char* str, const char* pattern) {
    try {
        std::regex re(pattern);
        return std::regex_match(str, re) ? 1.0 : 0.0;
    } catch (const std::regex_error& e) {
        throw_error_event("Regex error: " + std::string(e.what()));
        return 0.0;
    }
}

// Return matches result as json array.
DYCORE_API const char* DyCore_regex_match_ext(const char* str,
                                              const char* pattern) {
    static string returnBuffer;
    try {
        std::regex re(pattern);
        std::cmatch matches;
        if (std::regex_match(str, matches, re)) {
            json j = json::array();
            for (const auto& match : matches) {
                j.push_back(match.str());
            }
            returnBuffer = j.dump();
            return returnBuffer.c_str();
        } else {
            return "";
        }
    } catch (const std::exception& e) {
        throw_error_event("Regex error: " + std::string(e.what()));
        return "";
    }
}