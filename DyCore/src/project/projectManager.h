#pragma once
#include <atomic>
#include <cstdint>
#include <mutex>
#include <shared_mutex>

#include "colorKeyframe.h"
#include "json.hpp"
#include "project.h"

class ProjectManager {
   public:
    static ProjectManager &inst() {
        static ProjectManager instance;
        return instance;
    }

   private:
    mutable std::shared_mutex mtx;
    mutable std::mutex audioMtx;

    Project project;
    fs::path projectFilePath;
    fs::path projectDirPath;
    std::atomic<uint64_t> chartMusicLoadRequestId = 0;
    std::atomic<uint64_t> projectGeneration = 0;

    int currentChartIndex;
    uint64_t chartMetadataLastModifiedTime = 0;
    bool is_current_chart_set();
    bool check_current_chart_set();
    Chart &get_current_chart();

    void load_all_audio_data();

   public:
    ProjectManager() {
        setup_default_chart();
    }

    void setup_default_chart();

    void clear_project();
    void load_project(const Project &proj);
    void load_project_from_file(const char *filePath);
    int get_chart_count() const;
    int get_current_chart_index() const;
    void set_current_chart(int index);
    // Update timing points and notes to the current chart.
    void update_current_chart();
    /// Create a chart slot at the given difficulty.
    /// copyFromCurrent=true copies notes+timing+colorKeyframes;
    /// false creates a blank chart that still keeps the current timing points.
    /// @return New chart index, or -1 on failure.
    int create_chart(int difficulty, bool copyFromCurrent);
    /// Delete the current chart and switch to an adjacent remaining one.
    /// @return New current chart index, or -1 if deletion is not allowed.
    int delete_current_chart();
    /// @return Index of the chart with this difficulty, or -1.
    int find_chart_by_difficulty(int difficulty) const;
    /// @return Array of difficulty values for every stored chart.
    std::vector<int> get_chart_difficulties() const;
    /// Snapshot the current chart as a single-chart project (feature off).
    Project create_single_chart_export_snapshot();
    uint64_t get_project_generation() const {
        return projectGeneration.load();
    }
    // Call before replacing the live editor pools, including GML map_close.
    void invalidate_pending_saves();
    Project create_save_snapshot(uint64_t expectedGeneration);

    /// Getters & Setters

    void set_chart_metadata(const ChartMetadata &meta);
    ChartMetadata get_chart_metadata();
    uint64_t get_chart_metadata_last_modified_time() const;
    void set_chart_path(const ChartPath &path);
    ChartPath get_chart_path();
    void set_project_metadata(const nlohmann::json &meta);
    nlohmann::json get_project_metadata() const;
    void set_version(const string &ver);
    string get_version() const;

    string get_project_path() const {
        return projectFilePath.string();
    }
    string get_project_dir_path() const {
        return projectDirPath.string();
    }

    string get_full_path(const char *relativePath) const;

    // Loads audio data for the current chart.
    int load_chart_audio(const char *filePath);
    void unload_chart_audio();

    // Color keyframe management (synced from Chart.colorKeyframes).
    void get_color_keyframes(std::vector<ColorKeyframe> &out);
    void set_color_keyframes(const std::vector<ColorKeyframe> &kfs);
    void insert_color_keyframe(const ColorKeyframe &ck);
    void delete_color_keyframe(double time);
    void change_color_keyframe(double time, int color, ColorInterp interp);
    void clear_color_keyframes();

    // Color timeline toggle.
    bool get_color_timeline_enabled();
    void set_color_timeline_enabled(bool enabled);

    std::string dump() const;
};
