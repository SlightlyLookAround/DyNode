#include "timing.h"

#include <algorithm>

TimingManager& get_timing_manager() {
    static TimingManager instance;
    return instance;
}

void TimingManager::clear() {
    timingPoints.clear();
    mark_modified();
}

void TimingManager::add_timing_point(TimingPoint timingPoint) {
    timingPoints.push_back(timingPoint);
    outOfOrder = true;
    mark_modified();
}

void TimingManager::sort() {
    if (!outOfOrder)
        return;
    outOfOrder = false;
    std::sort(timingPoints.begin(), timingPoints.end(),
              [](const TimingPoint& a, const TimingPoint& b) {
                  return a.time < b.time;
              });
    mark_modified();
}

void TimingManager::append_timing_points(
    const std::vector<TimingPoint>& points) {
    timingPoints.insert(timingPoints.end(), points.begin(), points.end());
    outOfOrder = true;
    mark_modified();
}

void TimingManager::get_timing_points(std::vector<TimingPoint>& outPoints) {
    sort();
    outPoints = timingPoints;
}

const double TIMING_POINT_EPSILON = 1;
bool TimingManager::has_timing_point_at(double time) {
    sort();
    auto it = std::lower_bound(
        timingPoints.begin(), timingPoints.end(), time,
        [](const TimingPoint& a, double b) { return a.time < b; });

    // Check the element at the found position (or the one after the target
    // time)
    if (it != timingPoints.end()) {
        if (std::abs(it->time - time) < TIMING_POINT_EPSILON) {
            return true;
        }
    }

    // Check the element before the found position (the one before the target
    // time)
    if (it != timingPoints.begin()) {
        auto prev_it = std::prev(it);
        if (std::abs(prev_it->time - time) < TIMING_POINT_EPSILON) {
            return true;
        }
    }

    return false;
}

bool TimingManager::get_timing_point_at(double time, TimingPoint& outPoint) {
    sort();
    if (timingPoints.empty()) {
        return false;
    }

    auto it = std::upper_bound(timingPoints.begin(), timingPoints.end(), time,
                               [](double value, const TimingPoint& point) {
                                   return value < point.time;
                               });

    if (it == timingPoints.begin()) {
        outPoint = *it;
    } else {
        outPoint = *std::prev(it);
    }
    return true;
}

void TimingManager::change_timing_point_at_time(double time,
                                                const TimingPoint& tp) {
    for (auto& point : timingPoints) {
        if (point.time == time) {
            point = tp;
            mark_modified();
            return;
        }
    }
}

void TimingManager::delete_timing_point_at_time(double time) {
    timingPoints.erase(std::remove_if(timingPoints.begin(), timingPoints.end(),
                                      [time](const TimingPoint& point) {
                                          return point.time == time;
                                      }),
                       timingPoints.end());
    mark_modified();
}

void TimingManager::add_offset(double offset) {
    for (auto& point : timingPoints) {
        point.time += offset;
    }
    mark_modified();
}

void TimingManager::rebuild_segment_table() {
    if (segmentTableBuiltTime == lastModifiedTime)
        return;
    sort();
    segmentTable.clear();
    segmentTable.reserve(timingPoints.size());
    double totalBars = 1.0;
    for (size_t i = 0; i < timingPoints.size(); i++) {
        segmentTable.push_back({timingPoints[i].time, timingPoints[i].beatLength,
                                timingPoints[i].meter, totalBars});
        if (i + 1 < timingPoints.size()) {
            totalBars += std::ceil((timingPoints[i + 1].time - timingPoints[i].time) /
                                   (timingPoints[i].beatLength * timingPoints[i].meter));
        }
    }
    segmentTableBuiltTime = lastModifiedTime;
}

double TimingManager::time_to_bar(double time) {
    rebuild_segment_table();
    if (segmentTable.empty())
        return 0;

    // Binary search: find last segment with segment.time <= time (+1ms error correction).
    auto it = std::upper_bound(
        segmentTable.begin(), segmentTable.end(), time + 1.0,
        [](double t, const TimingSegment& s) { return t < s.time; });
    if (it != segmentTable.begin())
        --it;

    const auto& seg = *it;
    double nowBeats = (time - seg.time) / seg.beatLength;
    double nowBars = nowBeats / seg.meter;
    return seg.barOffset + nowBars;
}

double TimingManager::bar_to_time(double bar) {
    rebuild_segment_table();
    if (segmentTable.empty() || bar <= 0)
        return 0;

    // Binary search: find last segment with segment.barOffset <= bar.
    auto it = std::upper_bound(
        segmentTable.begin(), segmentTable.end(), bar,
        [](double b, const TimingSegment& s) { return b < s.barOffset; });
    if (it != segmentTable.begin())
        --it;

    const auto& seg = *it;
    double remainingBars = bar - seg.barOffset;
    double remainingBeats = remainingBars * seg.meter;
    return seg.time + remainingBeats * seg.beatLength;
}

double TimingManager::time_add_bar_delta(double time, double deltaBars) {
    if (deltaBars == 0)
        return time;
    double bar = time_to_bar(time);
    return bar_to_time(bar + deltaBars);
}
