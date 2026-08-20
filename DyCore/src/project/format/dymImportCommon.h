#pragma once

#include <string>
#include <unordered_map>
#include <vector>

struct DYMNotedata {
    std::string id;
    std::string subid;
    int type = 0;
    int side = 0;
    double bar = 0.0;
    double position = 0.0;
    double width = 0.0;
    double time = 0.0;
};

struct DYMTimingData {
    double time = 0.0;
    double barPerMinute = 0.0;
};

inline double imported_bar_to_time(double offset, double barPerMinute) {
    return (offset * 60000.0) / barPerMinute;
}

void import_timing_points(bool importTiming, bool hasTimingData,
                          const std::vector<DYMTimingData>& timings,
                          double offset, double barPerMin);

void fix_imported_note_times(std::vector<DYMNotedata>& notes,
                             const std::vector<DYMTimingData>& timings,
                             double offset, double barPerMin,
                             bool useParallel = true);

std::unordered_map<std::string, double> build_note_id_time_map(
    const std::vector<DYMNotedata>& notes);

void add_imported_notes_to_project(
    const std::vector<DYMNotedata>& notes,
    const std::unordered_map<std::string, double>& noteIDTimeMap);
