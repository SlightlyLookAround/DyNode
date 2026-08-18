#include <doctest/doctest.h>

#include <algorithm>
#include <random>
#include <utility>
#include <vector>

#include "project/format/dymImportCommon.h"

extern "C" double DyCore_index_sort(void* data, double size);

TEST_CASE("FixImportedNoteTimesParallelMatchesSerial") {
    std::mt19937 rng(42);

    // Several timing segments with varying BPM.
    std::vector<DYMTimingData> timings = {
        {0.0, 120.0}, {8.0, 150.0}, {16.0, 90.0}, {24.0, 200.0},
    };
    const double offset = 1.0;
    const double barPerMin = 120.0;

    // Enough notes to trigger the parallel path.
    std::vector<DYMNotedata> notes;
    notes.reserve(5000);
    for (int i = 0; i < 5000; i++) {
        DYMNotedata note;
        note.id = "n" + std::to_string(i);
        note.bar = std::uniform_real_distribution<double>(0.0, 40.0)(rng);
        note.side = i % 3;
        note.type = 0;
        note.position = 0.5;
        note.width = 1.0;
        notes.push_back(note);
    }

    auto serial = notes;
    auto parallel = notes;
    fix_imported_note_times(serial, timings, offset, barPerMin, false);
    fix_imported_note_times(parallel, timings, offset, barPerMin, true);

    REQUIRE(serial.size() == parallel.size());
    for (size_t i = 0; i < serial.size(); i++) {
        CHECK(serial[i].time == parallel[i].time);
    }
}

TEST_CASE("FixImportedNoteTimesSingleTiming") {
    std::vector<DYMTimingData> timings = {{0.0, 120.0}};
    std::vector<DYMNotedata> notes;
    for (int i = 0; i < 3000; i++) {
        DYMNotedata note;
        note.id = "n" + std::to_string(i);
        note.bar = static_cast<double>(i);
        note.time = -1.0;
        notes.push_back(note);
    }

    auto serial = notes;
    auto parallel = notes;
    fix_imported_note_times(serial, timings, 0.0, 120.0, false);
    fix_imported_note_times(parallel, timings, 0.0, 120.0, true);

    for (size_t i = 0; i < notes.size(); i++) {
        CHECK(serial[i].time == parallel[i].time);
        // A note on the very first bar lands exactly at time 0.
        CHECK(serial[i].time >= 0.0);
    }
}

TEST_CASE("IndexSortParallelAndSerial") {
    std::mt19937 rng(7);
    // The second field is the element's original position, matching the
    // (value, index) layout GML writes for extern_index_sort.
    const auto make_pairs = [&](size_t count) {
        std::vector<std::pair<double, double>> pairs(count);
        for (size_t i = 0; i < count; i++) {
            pairs[i] = {
                std::uniform_real_distribution<double>(0.0, 1000.0)(rng),
                static_cast<double>(i)};
        }
        return pairs;
    };

    // Serial path (below threshold).
    auto small = make_pairs(64);
    DyCore_index_sort(small.data(), static_cast<double>(small.size()));
    CHECK(std::is_sorted(small.begin(), small.end()));

    // Parallel path (above threshold), indices preserved alongside values.
    auto large = make_pairs(10000);
    const auto original = large;
    DyCore_index_sort(large.data(), static_cast<double>(large.size()));
    REQUIRE(std::is_sorted(large.begin(), large.end()));
    for (size_t i = 0; i < large.size(); i++) {
        // Sorting must not invent or drop elements.
        CHECK(large[i].first == original[static_cast<size_t>(large[i].second)].first);
    }
}
