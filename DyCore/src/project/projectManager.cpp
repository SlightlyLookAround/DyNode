#include "projectManager.h"

#include <mutex>
#include <shared_mutex>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#include <unordered_set>

#include "format/dyn.h"
#include "note.h"
#include "notePoolManager.h"
#include "project.h"
#include "colorKeyframe.h"
#include "timing.h"
#include "utils/backgroundTasks.h"
#include "utils.h"

bool ProjectManager::is_current_chart_set() {
    return currentChartIndex != -1;
}

bool ProjectManager::check_current_chart_set() {
    if (currentChartIndex < 0 || currentChartIndex >= get_chart_count()) {
        return false;
    }
    return true;
}

int ProjectManager::get_chart_count() const {
    return project.charts.size();
}

int ProjectManager::get_current_chart_index() const {
    return currentChartIndex;
}

namespace {
void load_notes_preserving_ids(const std::vector<Note>& notes) {
    auto& pool = get_note_pool_manager();
    pool.clear_notes();
    for (const auto& note : notes) {
        if (note.noteID.empty()) {
            create_note(note);
            continue;
        }
        Note n = note;
        if (n.get_note_type() == NOTE_TYPE::HOLD && !n.subNoteID.empty()) {
            Note sub = n;
            std::swap(sub.noteID, sub.subNoteID);
            sub.time = n.time + n.lastTime;
            sub.lastTime = 0;
            sub.beginTime = n.time;
            sub.type = static_cast<int>(NOTE_TYPE::SUB);
            if (!note_exists(sub.noteID)) {
                insert_note(sub);
            }
        }
        if (!note_exists(n.noteID)) {
            insert_note(n);
        } else {
            pool.set_note(n);
        }
    }
}
}  // namespace

void ProjectManager::set_current_chart(int index) {
    if (index < 0 || index >= get_chart_count()) {
        throw std::out_of_range("Chart index out of range");
    }
    currentChartIndex = index;
    chartMetadataLastModifiedTime++;

    auto &currentChart = get_current_chart();
    // Set notes. Preserve IDs when present so per-difficulty undo stays valid
    // across in-session chart switches.
    load_notes_preserving_ids(currentChart.notes);

    // Set timing points.
    get_timing_manager().clear();
    get_timing_manager().append_timing_points(currentChart.timingPoints);

    print_debug_message("Current chart set to: " + currentChart.metadata.title +
                        " difficulty=" +
                        std::to_string(currentChart.metadata.difficulty) +
                        " index=" + std::to_string(index));
}

int ProjectManager::create_chart(int difficulty, bool copyFromCurrent) {
    if (!check_current_chart_set()) {
        print_debug_message("Current chart is not set. Cannot create chart.");
        return -1;
    }

    Chart newChart;
    {
        std::shared_lock<std::shared_mutex> lock(mtx);
        auto &src = get_current_chart();
        newChart.metadata = src.metadata;
        newChart.metadata.difficulty = difficulty;
        newChart.path = src.path;
        if (copyFromCurrent) {
            newChart.notes = src.notes;
            newChart.timingPoints = src.timingPoints;
            newChart.colorKeyframes = src.colorKeyframes;
        } else {
            // Blank difficulty difference keeps the source timing points.
            newChart.notes.clear();
            newChart.timingPoints = src.timingPoints;
            newChart.colorKeyframes.clear();
        }
    }

    std::lock_guard<std::shared_mutex> lock(mtx);
    ++projectGeneration;
    project.charts.push_back(std::move(newChart));
    chartMetadataLastModifiedTime++;
    const int newIndex = static_cast<int>(project.charts.size()) - 1;
    print_debug_message("Created chart difficulty=" + std::to_string(difficulty) +
                        " index=" + std::to_string(newIndex) +
                        (copyFromCurrent ? " (copy)" : " (blank)"));
    return newIndex;
}

int ProjectManager::delete_current_chart() {
    if (!check_current_chart_set()) {
        print_debug_message("Current chart is not set. Cannot delete chart.");
        return -1;
    }
    if (get_chart_count() <= 1) {
        print_debug_message("Cannot delete the last remaining chart.");
        return -1;
    }

    int newIndex = -1;
    {
        std::lock_guard<std::shared_mutex> lock(mtx);
        const int deletedIndex = currentChartIndex;
        project.charts.erase(project.charts.begin() + deletedIndex);
        ++projectGeneration;
        chartMetadataLastModifiedTime++;

        if (deletedIndex > 0)
            newIndex = deletedIndex - 1;
        else
            newIndex = 0;
        if (newIndex >= static_cast<int>(project.charts.size()))
            newIndex = static_cast<int>(project.charts.size()) - 1;
        currentChartIndex = newIndex;
    }

    // Load the adjacent chart into the live pools.
    Chart loaded;
    {
        std::shared_lock<std::shared_mutex> lock(mtx);
        if (newIndex < 0 || newIndex >= static_cast<int>(project.charts.size()))
            return -1;
        loaded = project.charts[newIndex];
    }
    load_notes_preserving_ids(loaded.notes);
    get_timing_manager().clear();
    get_timing_manager().append_timing_points(loaded.timingPoints);
    print_debug_message("Deleted chart, switched to index=" +
                        std::to_string(newIndex));
    return newIndex;
}

int ProjectManager::find_chart_by_difficulty(int difficulty) const {
    std::shared_lock<std::shared_mutex> lock(mtx);
    for (int i = 0; i < static_cast<int>(project.charts.size()); ++i) {
        if (project.charts[i].metadata.difficulty == difficulty)
            return i;
    }
    return -1;
}

std::vector<int> ProjectManager::get_chart_difficulties() const {
    std::shared_lock<std::shared_mutex> lock(mtx);
    std::vector<int> out;
    out.reserve(project.charts.size());
    for (const auto& chart : project.charts)
        out.push_back(chart.metadata.difficulty);
    return out;
}

Project ProjectManager::create_single_chart_export_snapshot() {
    update_current_chart();
    Project exportProject;
    {
        std::shared_lock<std::shared_mutex> lock(mtx);
        exportProject.version = project.version;
        exportProject.metadata = project.metadata;
        exportProject.colorTimelineEnabled = project.colorTimelineEnabled;
        if (!check_current_chart_set()) {
            throw std::runtime_error("Current chart is not set");
        }
        exportProject.charts.push_back(get_current_chart());
    }

    // Independent exported dyn files never enable difficulty-diff storage.
    if (!exportProject.metadata.is_object())
        exportProject.metadata = nlohmann::json::object();
    exportProject.metadata["difficultyDiff"] = {
        {"enabled", false}, {"created", false}, {"activeIndex", 0}};
    return exportProject;
}

Chart &ProjectManager::get_current_chart() {
    if (!check_current_chart_set()) {
        throw std::runtime_error("Current chart is not set");
    }
    return project.charts[currentChartIndex];
}

void ProjectManager::clear_project() {
    std::lock_guard<std::shared_mutex> lock(mtx);
    ++projectGeneration;
    ++chartMusicLoadRequestId;
    project = Project();
    currentChartIndex = -1;
    chartMetadataLastModifiedTime++;
}

// Loads audio data for all charts in the project.
void ProjectManager::load_all_audio_data() {
    // TODO: Not implemented yet, just a placeholder using miniaudio to load the
    // audio data.
    return;

    background_tasks::launch([this]() {
        std::lock_guard<std::mutex> lock(audioMtx);
        std::unordered_map<std::string, AudioData> loadedAudioCache;
        std::unordered_set<std::string> failedAudioPaths;

        for (auto &chart : project.charts) {
            const auto &musicPath = get_full_path(chart.path.music.c_str());
            if (musicPath.empty()) {
                continue;
            }

            if (auto it = loadedAudioCache.find(musicPath);
                it != loadedAudioCache.end()) {
                chart.audioData = it->second;
                continue;
            }

            if (failedAudioPaths.find(musicPath) != failedAudioPaths.end()) {
                continue;
            }

            AudioData audioData;
            if (load_audio(musicPath.c_str(), audioData) == 0) {
                print_debug_message(
                    "Loaded audio path: " + musicPath + ", totalSamples=" +
                    std::to_string(audioData.pcmData.size()) +
                    ", sampleRate=" + std::to_string(audioData.sampleRate) +
                    ", channels=" + std::to_string(audioData.channels));
                chart.audioData = audioData;
                loadedAudioCache.emplace(musicPath, std::move(audioData));
            } else {
                failedAudioPaths.insert(musicPath);
                print_debug_message("Failed to load audio for chart: " +
                                    chart.metadata.title);
            }
        }
    });
}

void ProjectManager::setup_default_chart() {
    std::lock_guard<std::shared_mutex> lock(mtx);
    ++projectGeneration;
    ++chartMusicLoadRequestId;

    Project defaultProject;
    defaultProject.charts.push_back(
        Chart{.metadata = {
                  .title = "Last Train at 25 O'clock",
                  .sideType = {"MIXER", "PAD"},
                  .difficulty = 3,
              }});
    project = std::move(defaultProject);
    chartMetadataLastModifiedTime++;

    set_current_chart(0);
}

void ProjectManager::load_project_from_file(const char *filePath) {
    clear_project();
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (project_import_dyn(filePath, project) != 0) {
        throw std::runtime_error("Failed to import DYN project file.");
    }

    projectFilePath = convert_char_to_path(filePath);
    projectDirPath = projectFilePath.parent_path();

    // TODO: (Future feature) Load audio data for all charts after loading the
    // project.

    // load_all_audio_data();

    // Restore the last active difficulty-diff chart when present.
    if (get_chart_count() > 0) {
        int activeIndex = 0;
        try {
            if (project.metadata.is_object() &&
                project.metadata.contains("difficultyDiff") &&
                project.metadata["difficultyDiff"].is_object() &&
                project.metadata["difficultyDiff"].contains("activeIndex")) {
                activeIndex =
                    project.metadata["difficultyDiff"]["activeIndex"].get<int>();
            }
        } catch (const std::exception&) {
            activeIndex = 0;
        }
        if (activeIndex < 0 || activeIndex >= get_chart_count())
            activeIndex = 0;
        set_current_chart(activeIndex);
    } else {
        throw std::runtime_error(
            "This project does not contain any chart. The project file may be "
            "corrupted.");
    }
}

void ProjectManager::update_current_chart() {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) {
        print_debug_message("Current chart is not set. Cannot update chart.");
        return;
    }
    auto &chart = get_current_chart();
    // Update timing points.
    get_timing_manager().get_timing_points(chart.timingPoints);
    // Update notes.
    get_note_pool_manager().get_notes(chart.notes, true);
}

void ProjectManager::invalidate_pending_saves() {
    std::lock_guard<std::shared_mutex> lock(mtx);
    ++projectGeneration;
}

Project ProjectManager::create_save_snapshot(uint64_t expectedGeneration) {
    std::shared_lock<std::shared_mutex> lock(mtx);
    if (expectedGeneration != projectGeneration.load()) {
        throw std::runtime_error(
            "Save cancelled: the project was closed before reading began.");
    }
    if (!check_current_chart_set()) {
        throw std::runtime_error("Current chart is not set");
    }
    Project snapshot = project;
    auto &chart = snapshot.charts[currentChartIndex];
    get_timing_manager().get_timing_points(chart.timingPoints);
    get_note_pool_manager().get_notes(chart.notes, true);
    return snapshot;
}

void ProjectManager::set_chart_metadata(const ChartMetadata &meta) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) {
        print_debug_message("Current chart is not set. Cannot set metadata.");
        return;
    }
    get_current_chart().metadata = meta;

    chartMetadataLastModifiedTime++;
}

ChartMetadata ProjectManager::get_chart_metadata() {
    std::shared_lock<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) {
        return ChartMetadata();
    }
    return get_current_chart().metadata;
}

uint64_t ProjectManager::get_chart_metadata_last_modified_time() const {
    return chartMetadataLastModifiedTime;
}

void ProjectManager::set_chart_path(const ChartPath &path) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) {
        print_debug_message("Current chart is not set. Cannot set path.");
        return;
    }
    get_current_chart().path = path;
}

ChartPath ProjectManager::get_chart_path() {
    std::shared_lock<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) {
        return ChartPath();
    }
    return get_current_chart().path;
}

void ProjectManager::set_version(const string &ver) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    project.version = ver;
}

string ProjectManager::get_version() const {
    std::shared_lock<std::shared_mutex> lock(mtx);
    return project.version;
}

string ProjectManager::get_full_path(const char *relativePath) const {
    // Judge if the path is already absolute.
    fs::path p = convert_char_to_path(relativePath);
    if (p.is_absolute()) {
        return p.string();
    }

    return (projectDirPath / fs::path(relativePath)).string();
}

int ProjectManager::load_chart_audio(const char *filePath) {
    // TODO: Not implemented yet, just a placeholder using miniaudio to load the
    // audio data.
    return 0;

    fs::path musicPath = get_full_path(filePath);

    int chartIndex = -1;
    uint64_t requestId = 0;
    std::string chartTitle;
    {
        std::shared_lock<std::shared_mutex> projectLock(mtx);
        std::lock_guard<std::mutex> audioLock(audioMtx);
        if (!check_current_chart_set()) {
            print_debug_message("Current chart is not set. Cannot load audio.");
            return -1;
        }
        auto &chart = get_current_chart();
        chart.audioData = AudioData();
        chart.audioLoaded = false;

        chartIndex = currentChartIndex;
        chartTitle = chart.metadata.title;
        requestId = ++chartMusicLoadRequestId;
    }

    background_tasks::launch(
        [this, musicPath, chartIndex, requestId, chartTitle]() {
            AudioData loadedAudio;
            if (load_audio(musicPath.string().c_str(), loadedAudio) != 0) {
                if (requestId != chartMusicLoadRequestId) {
                    return;
                }
                print_debug_message("Failed to load audio for chart: " +
                                    chartTitle);
                return;
            }

            std::shared_lock<std::shared_mutex> projectLock(mtx);
            std::lock_guard<std::mutex> audioLock(audioMtx);
            if (requestId != chartMusicLoadRequestId) {
                return;
            }
            if (chartIndex < 0 ||
                chartIndex >= static_cast<int>(project.charts.size())) {
                return;
            }

            auto &chart = project.charts[chartIndex];
            chart.audioData = std::move(loadedAudio);
            chart.audioLoaded = true;

            auto &audioData = chart.audioData;
            print_debug_message(
                "Loaded audio path: " + musicPath.string() +
                ", totalSamples=" + std::to_string(audioData.pcmData.size()) +
                ", sampleRate=" + std::to_string(audioData.sampleRate) +
                ", channels=" + std::to_string(audioData.channels));
        });

    return 0;
}

void ProjectManager::unload_chart_audio() {
    std::shared_lock<std::shared_mutex> projectLock(mtx);
    std::lock_guard<std::mutex> audioLock(audioMtx);
    ++chartMusicLoadRequestId;

    if (!check_current_chart_set()) {
        print_debug_message("Current chart is not set. Cannot unload audio.");
        return;
    }

    auto &chart = get_current_chart();
    if (chart.audioLoaded) {
        chart.audioData = AudioData();
        chart.audioLoaded = false;
        print_debug_message("Unloaded audio for chart: " +
                            chart.metadata.title);
    }
}

void ProjectManager::set_project_metadata(const nlohmann::json &meta) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    project.metadata = meta;
}

nlohmann::json ProjectManager::get_project_metadata() const {
    std::shared_lock<std::shared_mutex> lock(mtx);
    return project.metadata;
}

// =============================================================================
// Color Keyframe Management
// =============================================================================

void ProjectManager::get_color_keyframes(std::vector<ColorKeyframe> &out) {
    std::shared_lock<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) return;
    out = get_current_chart().colorKeyframes;
}

void ProjectManager::set_color_keyframes(
    const std::vector<ColorKeyframe> &kfs) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) return;
    get_current_chart().colorKeyframes = kfs;
    // Keep sorted.
    auto &v = get_current_chart().colorKeyframes;
    std::sort(v.begin(), v.end(),
              [](const ColorKeyframe &a, const ColorKeyframe &b) {
                  return a.time < b.time;
              });
}

void ProjectManager::insert_color_keyframe(const ColorKeyframe &ck) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) return;
    auto &kfs = get_current_chart().colorKeyframes;
    // Replace if same time exists (within 1ms tolerance).
    for (auto &existing : kfs) {
        if (std::abs(existing.time - ck.time) < 1.0) {
            existing = ck;
            return;
        }
    }
    kfs.push_back(ck);
    std::sort(kfs.begin(), kfs.end(),
              [](const ColorKeyframe &a, const ColorKeyframe &b) {
                  return a.time < b.time;
              });
}

void ProjectManager::delete_color_keyframe(double time) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) return;
    auto &kfs = get_current_chart().colorKeyframes;
    kfs.erase(std::remove_if(kfs.begin(), kfs.end(),
                             [time](const ColorKeyframe &ck) {
                                 return std::abs(ck.time - time) < 1.0;
                             }),
              kfs.end());
}

void ProjectManager::change_color_keyframe(double time, int color,
                                           ColorInterp interp) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) return;
    auto &kfs = get_current_chart().colorKeyframes;
    for (auto &ck : kfs) {
        if (std::abs(ck.time - time) < 1.0) {
            ck.color = color;
            ck.interp = interp;
            return;
        }
    }
}

void ProjectManager::clear_color_keyframes() {
    std::lock_guard<std::shared_mutex> lock(mtx);
    if (!check_current_chart_set()) return;
    get_current_chart().colorKeyframes.clear();
}

bool ProjectManager::get_color_timeline_enabled() {
    std::shared_lock<std::shared_mutex> lock(mtx);
    return project.colorTimelineEnabled;
}

void ProjectManager::set_color_timeline_enabled(bool enabled) {
    std::lock_guard<std::shared_mutex> lock(mtx);
    project.colorTimelineEnabled = enabled;
}

std::string ProjectManager::dump() const {
    std::shared_lock<std::shared_mutex> lock(mtx);
    return nlohmann::json(project).dump();
}
