#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <numeric>
#include <random>
#include <taskflow/algorithm/for_each.hpp>
#include <taskflow/taskflow.hpp>
#include <unordered_set>
#include <vector>
#include <xxhash/xxhash.h>

#include "api.h"
#include "bitio.h"
#include "note.h"
#include "notePoolManager.h"
#include "timing.h"
#include "utils.h"

// ===========================================================================
// DyCore_editor_fix_notes
// Parallel check + clamp all non-SUB notes whose position is out of screen.
// Returns the number of fixed notes.
// ===========================================================================
DYCORE_API double DyCore_editor_fix_notes() {
    return static_cast<double>(get_note_pool_manager().batch_fix_notes());
}

// ===========================================================================
// DyCore_timing_fix
// Parallel search + rescale notes in a timing segment after BPM change.
// Parameters:
//   tpBeforeTime, tpBeforeBeatLength — old timing point
//   tpAfterTime,  tpAfterBeatLength  — new timing point
//   nextTPTime — time of the next timing point (-1 if last segment)
// Returns: affected count (positive) or -(affected count) if cross-boundary warning.
// ===========================================================================
DYCORE_API double DyCore_timing_fix(double tpBeforeTime,
                                    double tpBeforeBeatLength,
                                    double tpAfterTime,
                                    double tpAfterBeatLength,
                                    double nextTPTime) {
    bool crossWarning = false;
    int count = get_note_pool_manager().batch_timing_fix(
        tpBeforeTime, tpBeforeBeatLength, tpAfterTime, tpAfterBeatLength,
        nextTPTime, crossWarning);
    double result = static_cast<double>(count);
    if (crossWarning)
        result = -result;
    return result;
}

// ===========================================================================
// DyCore_chart_randomize
// Parallel randomize position, side, width for all non-SUB notes.
// Writes original props into outBuffer for GML-side undo construction.
// Buffer format: [u32 count][count × (null-terminated noteID + side:4 + width:8 + position:8)]
// Returns: number of randomized notes.
// ===========================================================================
DYCORE_API double DyCore_chart_randomize(char* outBuffer) {
    return static_cast<double>(
        get_note_pool_manager().batch_randomize(outBuffer));
}

// ===========================================================================
// DyCore_trianglify_step
// Parallel point animation update for trianglify background.
// Buffer format (in/out): [u32 count][count × (f64 x, f64 y, f64 vx, f64 vy)]
// Returns: 0 on success.
// ===========================================================================
DYCORE_API double DyCore_trianglify_step(char* pointsBuf, double dt,
                                         double width, double height) {
    uint32_t count = 0;
    std::memcpy(&count, pointsBuf, sizeof(uint32_t));
    if (count == 0)
        return 0;

    // Each point: 4 doubles = 32 bytes, starting after the 4-byte header.
    struct PointData {
        double x, y, vx, vy;
    };

    auto* points = reinterpret_cast<PointData*>(pointsBuf + sizeof(uint32_t));

    tf::Taskflow taskflow;
    taskflow.for_each_index(
        0, static_cast<int>(count), 1, [&](int i) {
            auto& p = points[i];
            double dx = p.vx * dt;
            double dy = p.vy * dt;
            if (p.x + dx < 0.0 || p.x + dx > width)
                p.vx = -p.vx;
            if (p.y + dy < 0.0 || p.y + dy > height)
                p.vy = -p.vy;
            p.x += p.vx * dt;
            p.y += p.vy * dt;
        });
    get_shared_taskflow_executor().run(taskflow).wait();

    return 0;
}

// ===========================================================================
// DyCore_find_duplicate_notes
// Parallel hash computation + native hash set to find duplicate notes.
// Returns: JSON array string of duplicate noteIDs.
// ===========================================================================
DYCORE_API const char* DyCore_find_duplicate_notes() {
    static std::string result;
    result = get_note_pool_manager().batch_find_duplicates();
    return result.c_str();
}

// ===========================================================================
// Sampling helpers
// ===========================================================================

// Snap a time to the nearest beat subdivision grid.
// Simplified version of editor_snap_to_grid_y with ignore_boundary=true.
static double snap_to_grid_time(double time, double beatDiv) {
    auto& tm = get_timing_manager();
    TimingPoint tp;
    if (!tm.get_timing_point_at(time, tp))
        return time;

    double beatIndex = std::floor((time - tp.time) / tp.beatLength);
    double divDuration = tp.beatLength / beatDiv;
    double divIndexF = (time - beatIndex * tp.beatLength - tp.time) / divDuration;
    double snappedDiv = std::round(divIndexF);
    return snappedDiv * divDuration + beatIndex * tp.beatLength + tp.time;
}

// Centripetal Catmull-Rom spline evaluation via De Casteljau.
struct Vec2 {
    double x, y;
};

static Vec2 de_casteljau(double t0, double t1, double t2, double t3,
                         Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double t) {
    auto lerp_v = [](Vec2 a, Vec2 b, double ta, double tb, double t) -> Vec2 {
        double w = (tb - ta);
        if (std::abs(w) < 1e-12)
            return a;
        double wa = (tb - t) / w;
        double wb = (t - ta) / w;
        return {a.x * wa + b.x * wb, a.y * wa + b.y * wb};
    };
    Vec2 a1 = lerp_v(p0, p1, t0, t1, t);
    Vec2 a2 = lerp_v(p1, p2, t1, t2, t);
    Vec2 a3 = lerp_v(p2, p3, t2, t3, t);
    Vec2 b1 = lerp_v(a1, a2, t0, t2, t);
    Vec2 b2 = lerp_v(a2, a3, t1, t3, t);
    return lerp_v(b1, b2, t1, t2, t);
}

static double catmull_rom_eval(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3,
                               double targetY) {
    constexpr double eps = 0.0001;
    auto vec_len = [](Vec2 v) { return std::sqrt(v.x * v.x + v.y * v.y); };
    auto vec_sub = [](Vec2 a, Vec2 b) -> Vec2 { return {a.x - b.x, a.y - b.y}; };

    double t0 = 0;
    double t1 = std::max(std::pow(vec_len(vec_sub(p1, p0)), 0.5), eps);
    double t2 = std::max(std::pow(vec_len(vec_sub(p2, p1)), 0.5), eps) + t1;
    double t3 = std::max(std::pow(vec_len(vec_sub(p3, p2)), 0.5), eps) + t2;

    double tL = t1, tR = t2, tM = (t1 + t2) / 2;
    for (int i = 0; i < 16; i++) {
        tM = (tL + tR) / 2;
        Vec2 pM = de_casteljau(t0, t1, t2, t3, p0, p1, p2, p3, tM);
        if (pM.y < targetY)
            tL = tM;
        else
            tR = tM;
    }
    return de_casteljau(t0, t1, t2, t3, p0, p1, p2, p3, tM).x;
}

static double lagrange_3point(double tTarget, double t1, double v1,
                              double t2, double v2, double t3, double v3) {
    double L1 = ((tTarget - t2) * (tTarget - t3)) / ((t1 - t2) * (t1 - t3));
    double L2 = ((tTarget - t1) * (tTarget - t3)) / ((t2 - t1) * (t2 - t3));
    double L3 = ((tTarget - t1) * (tTarget - t2)) / ((t3 - t1) * (t3 - t2));
    return v1 * L1 + v2 * L2 + v3 * L3;
}

// ===========================================================================
// Sampling result record written to output buffer.
// Packed as: [u32 segmentIndex][f64 time][f64 position][f64 width]
// ===========================================================================
static void write_sample_record(char*& ptr, uint32_t segIdx, double time,
                                double position, double width) {
    bitwrite(ptr, segIdx);
    bitwrite(ptr, time);
    bitwrite(ptr, position);
    bitwrite(ptr, width);
}

// ===========================================================================
// DyCore_sample_notes
// Unified sampling: mode 0=linear, 1=cosine, 2=catmull-rom
// Input buffer: [u32 count][count × (f64 time, f64 position, f64 width, s32 side)]
// Output buffer: [u32 count][count × (u32 segIdx, f64 time, f64 position, f64 width)]
// Returns: number of sample records written.
// ===========================================================================
DYCORE_API double DyCore_sample_notes(const char* controlPointsBuf,
                                      double beatDiv, double mode,
                                      char* outBuffer) {
    const char* readPtr = controlPointsBuf;
    uint32_t cpCount = 0;
    bitread(readPtr, cpCount);
    if (cpCount < 2) {
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }

    struct ControlPoint {
        double time, position, width;
        int side;
    };
    std::vector<ControlPoint> cps(cpCount);
    for (uint32_t i = 0; i < cpCount; i++) {
        bitread(readPtr, cps[i].time);
        bitread(readPtr, cps[i].position);
        bitread(readPtr, cps[i].width);
        bitread(readPtr, cps[i].side);
    }

    // Catmull-Rom: duplicate first/last as ghost endpoints.
    // For cpCount >= 4: Lagrange 3-point extrapolation (matches original GML).
    // For cpCount < 4: duplicate nearest endpoint (avoids degenerate extrapolation
    // that references uncomputed ghost points or causes division by zero).
    struct CRPoint {
        double time, position, width;
    };
    std::vector<CRPoint> crPts;
    if (static_cast<int>(mode) == 2) {
        crPts.resize(cpCount + 2);
        for (uint32_t i = 0; i < cpCount; i++) {
            crPts[i + 1] = {cps[i].time, cps[i].position, cps[i].width};
        }
        // Mirror ghost time values.
        crPts[0].time = 2 * crPts[1].time - crPts[2].time;
        crPts[cpCount + 1].time =
            2 * crPts[cpCount].time - crPts[cpCount - 1].time;
        // Position/width for ghost endpoints.
        if (cpCount >= 4) {
            crPts[0].position = lagrange_3point(
                crPts[0].time, crPts[1].time, crPts[1].position,
                crPts[2].time, crPts[2].position,
                crPts[3].time, crPts[3].position);
            crPts[0].width = lagrange_3point(
                crPts[0].time, crPts[1].time, crPts[1].width,
                crPts[2].time, crPts[2].width,
                crPts[3].time, crPts[3].width);
            crPts[cpCount + 1].position = lagrange_3point(
                crPts[cpCount + 1].time,
                crPts[cpCount].time, crPts[cpCount].position,
                crPts[cpCount - 1].time, crPts[cpCount - 1].position,
                crPts[cpCount - 2].time, crPts[cpCount - 2].position);
            crPts[cpCount + 1].width = lagrange_3point(
                crPts[cpCount + 1].time,
                crPts[cpCount].time, crPts[cpCount].width,
                crPts[cpCount - 1].time, crPts[cpCount - 1].width,
                crPts[cpCount - 2].time, crPts[cpCount - 2].width);
        } else {
            crPts[0].position = crPts[1].position;
            crPts[0].width = crPts[1].width;
            crPts[cpCount + 1].position = crPts[cpCount].position;
            crPts[cpCount + 1].width = crPts[cpCount].width;
        }
    }

    // Generate samples.
    struct SampleRecord {
        uint32_t segIdx;
        double time, position, width;
    };
    std::vector<SampleRecord> results;

    auto& tm = get_timing_manager();
    for (uint32_t seg = 0; seg + 1 < cpCount; seg++) {
        const auto& note = cps[seg];
        const auto& nextNote = cps[seg + 1];
        double segmentDuration = nextNote.time - note.time;
        if (segmentDuration <= 0)
            continue;

        double currentTime = note.time;
        TimingPoint currentTP;
        if (!tm.get_timing_point_at(currentTime, currentTP))
            continue;
        currentTime += currentTP.beatLength / beatDiv;
        currentTime = snap_to_grid_time(currentTime, beatDiv);

        while (currentTime < nextNote.time) {
            double ratio = (currentTime - note.time) / segmentDuration;
            double pos, wid;

            switch (static_cast<int>(mode)) {
                case 0:  // Linear
                    pos = note.position + (nextNote.position - note.position) * ratio;
                    wid = note.width + (nextNote.width - note.width) * ratio;
                    break;
                case 1:  // Cosine
                {
                    double t2 = (1 - std::cos(ratio * 3.14159265358979323846)) / 2;
                    pos = note.position * (1 - t2) + nextNote.position * t2;
                    wid = note.width * (1 - t2) + nextNote.width * t2;
                    break;
                }
                case 2:  // Catmull-Rom
                {
                    const auto& p0 = crPts[seg];
                    const auto& p1 = crPts[seg + 1];
                    const auto& p2 = crPts[seg + 2];
                    const auto& p3 = crPts[seg + 3];
                    pos = catmull_rom_eval({p0.position, p0.time}, {p1.position, p1.time},
                                          {p2.position, p2.time}, {p3.position, p3.time},
                                          currentTime);
                    wid = catmull_rom_eval({p0.width, p0.time}, {p1.width, p1.time},
                                          {p2.width, p2.time}, {p3.width, p3.time},
                                          currentTime);
                    break;
                }
                default:
                    pos = note.position;
                    wid = note.width;
            }

            results.push_back({static_cast<uint32_t>(seg), currentTime, pos, wid});

            double prevTime = currentTime;
            if (!tm.get_timing_point_at(currentTime, currentTP))
                break;
            currentTime += currentTP.beatLength / beatDiv;
            currentTime = snap_to_grid_time(currentTime, beatDiv);

            if (currentTime <= prevTime)
                break;
        }
    }

    // Write output.
    char* writePtr = outBuffer;
    uint32_t resultCount = static_cast<uint32_t>(results.size());
    std::memcpy(writePtr, &resultCount, sizeof(uint32_t));
    writePtr += sizeof(uint32_t);
    for (const auto& r : results) {
        write_sample_record(writePtr, r.segIdx, r.time, r.position, r.width);
    }

    return static_cast<double>(resultCount);
}

// ===========================================================================
// DyCore_compute_beatlines
// Batch compute all visible beatline geometry data.
// Input: runtime state scalars + JSON config.
// Output buffer: [u32 count][count × line descriptor]
// Returns: number of line descriptors written.
// ===========================================================================

static constexpr double BASE_RES_W_BL = 1920.0;
static constexpr double BASE_RES_H_BL = 1080.0;

struct BeatlineDescriptor {
    // Down lane
    double dx1, dy1, dx2, dy2;
    // Left lane
    double lx1, ly1, lx2, ly2;
    // Right lane
    double rx1, ry1, rx2, ry2;
    uint32_t color;
    double alphaDown, alphaLeft, alphaRight;
    double thickness;
    uint32_t isHard;
    // Text info
    double textX, textY;
    uint32_t totalBeats;
    uint32_t beatIndex;
    uint32_t meter;
    double beatLength;
    uint32_t divLevel;
};

static double note_time_to_y_bl(double time, int side, double nowTime,
                                double playbackSpeed, double targetLineBelow,
                                double targetLineBeside) {
    if (side == 0) {
        return BASE_RES_H_BL - targetLineBelow -
               (time - nowTime) * playbackSpeed;
    }
    double y = BASE_RES_W_BL / 2.0 +
               (side == 1 ? -1.0 : 1.0) *
                   (BASE_RES_W_BL / 2.0 -
                    (playbackSpeed * (time - nowTime)) - targetLineBeside);
    return y;
}

DYCORE_API double DyCore_compute_beatlines(const char* configBuf,
                                            char* outBuffer) {
    try {
    auto config = nlohmann::json::parse(configBuf, nullptr, false);
    if (config.is_discarded()) {
        print_debug_message("DyCore_compute_beatlines: JSON parse failed");
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }

    double nowTime = config.value("nowTime", 0.0);
    double playbackSpeed = config.value("playbackSpeed", 1.0);
    double targetLineBelow = config.value("targetLineBelow", 0.0);
    double targetLineBeside = config.value("targetLineBeside", 0.0);
    double beatDiv = config.value("beatDiv", 1.0);
    double musicLength = config.value("musicLength", 0.0);
    double beatlineAlphaDown = config.value("alphaDown", 0.0);
    double beatlineAlphaLeft = config.value("alphaLeft", 0.0);
    double beatlineAlphaRight = config.value("alphaRight", 0.0);
    double beatlineAlphaMul = config.value("alphaMul", 0.0);

    auto& tm = get_timing_manager();
    tm.sort();
    const int tpCount = tm.size();
    if (tpCount == 0 || beatlineAlphaMul <= 0.01) {
        print_debug_message("DyCore_compute_beatlines: early exit tpCount=" + std::to_string(tpCount) + " alphaMul=" + std::to_string(beatlineAlphaMul));
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }

    bool beatlineVisible =
        (beatlineAlphaDown + beatlineAlphaLeft + beatlineAlphaRight) > 0.01;
    if (!beatlineVisible) {
        print_debug_message("DyCore_compute_beatlines: not visible");
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }

    auto enabled = config.value("enabled", std::vector<int>(129, 0));
    auto colors = config.value("colors", std::vector<uint32_t>(30, 0x757575));
    auto lengthOffset = config.value("lengthOffset", std::vector<int>(30, 0));
    auto style = config.value("style", 0);
    double hardWidth = config.value("hardWidth", 3.5);
    double normalWidth = config.value("normalWidth", 2.0);
    double hardLength = config.value("hardLength", 1728.0);
    double normalLength = config.value("normalLength", 1440.0);
    double longLength = config.value("longLength", 1440.0);
    double hardHeight = config.value("hardHeight", 950.0);
    double normalHeight = config.value("normalHeight", 900.0);
    int maxDiv = config.value("maxDiv", 128);
    double sideInfoX = config.value("sideInfoX", 1100.0);

    int shortestOffset = 0;
    for (size_t i = 1; i < lengthOffset.size(); i++)
        shortestOffset = std::min(shortestOffset, lengthOffset[i]);
    shortestOffset -= 10;

    // Load timing points into local vector, skipping invalid entries.
    std::vector<TimingPoint> tps;
    tps.reserve(tpCount);
    for (int i = 0; i < tpCount; i++) {
        auto tp = tm[i];
        if (tp.beatLength > 0 && tp.meter > 0)
            tps.push_back(tp);
    }
    if (tps.empty()) {
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }
    const int validTpCount = static_cast<int>(tps.size());

    // Find current timing point.
    int nowat = 0;
    int totalBeats = 0;
    while (nowat + 1 < validTpCount && tps[nowat + 1].time <= nowTime) {
        totalBeats += static_cast<int>(std::ceil(
            (tps[nowat + 1].time - tps[nowat].time) /
            (tps[nowat].beatLength * tps[nowat].meter)));
        nowat++;
    }

    std::vector<BeatlineDescriptor> lines;

    // Iterate timing points (replicates the outer while loop).
    while (true) {
        double nowTpTime = tps[nowat].time;
        double nextTpTime =
            (nowat + 1 == validTpCount) ? musicLength : tps[nowat + 1].time;
        int nowBeats =
            (nowat == 0)
                ? static_cast<int>(
                      std::floor((nowTime - nowTpTime) / tps[nowat].beatLength))
                : 0;

        double tpBeatLen = tps[nowat].beatLength;
        int tpMeter = tps[nowat].meter;

        // Iterate beats (match original GML: loop condition uses subdivision time, not beat time).
        for (int i = nowBeats;; i++) {
            // Check beat start time is within segment.
            if (i * tpBeatLen + nowTpTime + 1 >= nextTpTime)
                break;
            // Check beat is within visible screen area.
            if ((i * tpBeatLen + nowTpTime - nowTime) * playbackSpeed > BASE_RES_H_BL)
                break;

            // Iterate division levels.
            for (int j = maxDiv; j >= 1; j--) {
                if (j != static_cast<int>(beatDiv) &&
                    (j >= static_cast<int>(enabled.size()) || enabled[j] == 0))
                    continue;

                // Iterate sub-divisions.
                for (double k = (j == 1 ? 0.0 : 1.0 / j);
                     k < 1.0 &&
                     (i + k) * tpBeatLen + nowTpTime < nextTpTime;
                     k += ((j & 1) ? 1.0 : 2.0) / j) {
                    double t = nowTpTime + (i + k) * tpBeatLen;

                    // Per-subdivision screen cull (matches original GML).
                    double ny_check = note_time_to_y_bl(
                        t, 0, nowTime, playbackSpeed, targetLineBelow,
                        targetLineBeside);
                    double nyl_check = note_time_to_y_bl(
                        t, 1, nowTime, playbackSpeed, targetLineBelow,
                        targetLineBeside);
                    if (ny_check < 0 && nyl_check > BASE_RES_W_BL / 2)
                        break;

                    double ny = ny_check;
                    double nyl = note_time_to_y_bl(
                        t, 1, nowTime, playbackSpeed, targetLineBelow,
                        targetLineBeside);
                    double nyr = note_time_to_y_bl(
                        t, 2, nowTime, playbackSpeed, targetLineBelow,
                        targetLineBeside);

                    bool nowHard = (k == 0 && i % tpMeter == 0);
                    double nowW =
                        nowHard ? hardWidth : normalWidth;
                    double nowL =
                        nowHard ? hardLength : normalLength;
                    double nowH =
                        nowHard ? hardHeight : normalHeight;
                    nowW *= 3.0;

                    if (j < static_cast<int>(lengthOffset.size()))
                        nowL += lengthOffset[j];
                    else
                        nowL += shortestOffset - j;

                    // Culling.
                    if (ny < 0 && nyl > BASE_RES_W_BL / 2)
                        break;

                    // Style overrides.
                    if (style == 1 || style == 2)  // MONO or MONOLONG
                        nowL = nowHard ? hardLength : longLength;

                    // Color.
                    uint32_t ncol = 0x757575;  // c_grey
                    if (j < static_cast<int>(colors.size()) && colors[j] != 0)
                        ncol = colors[j];
                    if (style == 1 || style == 2)  // MONO or MONOLONG
                        ncol = nowHard ? 0xFFFFFF : 0xC0C0C0;

                    BeatlineDescriptor desc{};
                    // Down lane
                    desc.dx1 = BASE_RES_W_BL / 2.0 - nowL / 2.0;
                    desc.dy1 = ny;
                    desc.dx2 = BASE_RES_W_BL / 2.0 + nowL / 2.0;
                    desc.dy2 = ny;
                    // Left lane
                    desc.lx1 = nyl;
                    desc.ly1 = BASE_RES_H_BL - targetLineBelow - nowH;
                    desc.lx2 = nyl;
                    desc.ly2 = BASE_RES_H_BL - targetLineBelow;
                    // Right lane
                    desc.rx1 = nyr;
                    desc.ry1 = BASE_RES_H_BL - targetLineBelow - nowH;
                    desc.rx2 = nyr;
                    desc.ry2 = BASE_RES_H_BL - targetLineBelow;

                    desc.color = ncol;
                    desc.alphaDown = beatlineAlphaDown;
                    desc.alphaLeft = beatlineAlphaLeft;
                    desc.alphaRight = beatlineAlphaRight;
                    desc.thickness = nowW;
                    desc.isHard = nowHard ? 1 : 0;
                    desc.textX = sideInfoX;
                    desc.textY = ny;
                    desc.totalBeats = totalBeats;
                    desc.beatIndex = static_cast<uint32_t>(i);
                    desc.meter = static_cast<uint32_t>(tpMeter);
                    desc.beatLength = tpBeatLen;
                    desc.divLevel = static_cast<uint32_t>(j);

                    lines.push_back(desc);
                }
            }
        }

        // Advance to next timing point.
        totalBeats += static_cast<int>(std::ceil(
            (nextTpTime - nowTpTime) / (tpBeatLen * tpMeter)));
        nowat++;
        if (nowat >= validTpCount)
            break;
        if ((tps[nowat].time - nowTime) * playbackSpeed > BASE_RES_H_BL)
            break;
    }

    // Write output.
    char* writePtr = outBuffer;
    uint32_t lineCount = static_cast<uint32_t>(lines.size());
    print_debug_message("DyCore_compute_beatlines: nowTime=" + std::to_string(nowTime) + " spd=" + std::to_string(playbackSpeed) + " tBlw=" + std::to_string(targetLineBelow) + " tBsd=" + std::to_string(targetLineBeside) + " beatDiv=" + std::to_string(beatDiv) + " musicLen=" + std::to_string(musicLength) + " aDown=" + std::to_string(beatlineAlphaDown) + " aMul=" + std::to_string(beatlineAlphaMul) + " tpCount=" + std::to_string(tpCount));
    std::memcpy(writePtr, &lineCount, sizeof(uint32_t));
    writePtr += sizeof(uint32_t);
    for (const auto& d : lines) {
        bitwrite(writePtr, d.dx1);
        bitwrite(writePtr, d.dy1);
        bitwrite(writePtr, d.dx2);
        bitwrite(writePtr, d.dy2);
        bitwrite(writePtr, d.lx1);
        bitwrite(writePtr, d.ly1);
        bitwrite(writePtr, d.lx2);
        bitwrite(writePtr, d.ly2);
        bitwrite(writePtr, d.rx1);
        bitwrite(writePtr, d.ry1);
        bitwrite(writePtr, d.rx2);
        bitwrite(writePtr, d.ry2);
        bitwrite(writePtr, d.color);
        bitwrite(writePtr, d.alphaDown);
        bitwrite(writePtr, d.alphaLeft);
        bitwrite(writePtr, d.alphaRight);
        bitwrite(writePtr, d.thickness);
        bitwrite(writePtr, d.isHard);
        bitwrite(writePtr, d.textX);
        bitwrite(writePtr, d.textY);
        bitwrite(writePtr, d.totalBeats);
        bitwrite(writePtr, d.beatIndex);
        bitwrite(writePtr, d.meter);
        bitwrite(writePtr, d.beatLength);
        bitwrite(writePtr, d.divLevel);
    }

    return static_cast<double>(lineCount);
    } catch (...) {
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }
}
