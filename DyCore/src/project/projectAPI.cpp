#include <fstream>
#include <memory>

#include "api.h"
#include "compress.h"
#include "format/dy.h"
#include "format/dyn.h"
#include "format/xml.h"
#include "gm.h"
#include "project.h"
#include "projectManager.h"
#include "utils.h"

// Invalidate unread saves and finish any active read before GML clears its
// pools.
DYCORE_API double DyCore_project_save_invalidate() {
    ProjectManager::inst().invalidate_pending_saves();
    return 0;
}

// Returns the accepted request ID, or -1 if no worker was dispatched.
DYCORE_API double DyCore_save_project_request(const char* filePath,
                                              double compressionLevel) {
    namespace fs = std::filesystem;
    try {
        if (!filePath || strlen(filePath) == 0) {
            throw std::runtime_error("File path is empty.");
        }
        const fs::path path = convert_char_to_path(filePath);
        const fs::path parentDir = path.parent_path();
        if (!parentDir.empty() && !fs::exists(parentDir)) {
            throw std::runtime_error("Parent directory does not exist.");
        }
        return static_cast<double>(save_project(filePath, compressionLevel));
    } catch (const std::exception& e) {
        throw_error_event(e.what());
        return -1;
    }
}

// Preserve the legacy return convention for existing native callers.
DYCORE_API double DyCore_save_project(const char* filePath,
                                      double compressionLevel) {
    return DyCore_save_project_request(filePath, compressionLevel) < 0 ? -1 : 0;
}

DYCORE_API const char* DyCore_get_notes_array_string() {
    static string notesArrayString;
    notesArrayString = get_notes_array_string();
    return notesArrayString.c_str();
}

DYCORE_API double DyCore_chart_import_xml(const char* filePath,
                                          double importInfo,
                                          double importTiming) {
    if (!filePath || strlen(filePath) == 0) {
        throw_error_event("File path is empty.");
        return -1;
    }

    return (double)chart_import_xml(filePath, importInfo > 0, importTiming > 0);
}

DYCORE_API double DyCore_chart_import_dy(const char* filePath,
                                         double importInfo,
                                         double importTiming) {
    if (!filePath || strlen(filePath) == 0) {
        throw_error_event("File path is empty.");
        return -1;
    }

    return (double)chart_import_dy(filePath, importInfo > 0, importTiming > 0);
}

DYCORE_API const char* DyCore_chart_import_dy_get_remix() {
    static string remix;
    remix = get_dy_remix();
    return remix.c_str();
}

DYCORE_API double DyCore_project_load(const char* filePath) {
    try {
        load_project(filePath);
    } catch (const std::exception& e) {
        print_debug_message("Project load failed: " + string(e.what()));
        gamemaker_announcement(GM_ANNOUNCEMENT_TYPE::ANNO_ERROR,
                               "anno_project_load_failed", {e.what()});
        return -1;
    }
    return 0;
}

DYCORE_API double DyCore_chart_import_dyn(const char* filePath,
                                          double importInfo,
                                          double importTiming) {
    if (!filePath || strlen(filePath) == 0) {
        throw_error_event("File path is empty.");
        return -1;
    }

    return chart_import_dyn(filePath, importInfo > 0, importTiming > 0);
}

DYCORE_API double DyCore_chart_export_xml(const char* filePath, double isDym,
                                          double fixError) {
    if (!filePath || strlen(filePath) == 0) {
        throw_error_event("File path is empty.");
        return -1;
    }

    try {
        chart_export_xml(filePath, isDym > 0, fixError);
    } catch (const std::exception& e) {
        print_debug_message("Failed to export XML file to " + string(filePath) +
                            ": " + e.what());
        return -1;
    }

    return 0;
}

DYCORE_API const char* DyCore_get_chart_metadata() {
    static string chartMetadata;
    chartMetadata = nlohmann::json(chart_get_metadata()).dump();
    return chartMetadata.c_str();
}

DYCORE_API double DyCore_get_chart_metadata_last_modified_time() {
    return ProjectManager::inst().get_chart_metadata_last_modified_time();
}

DYCORE_API const char* DyCore_get_chart_path() {
    static string chartPath;
    chartPath = nlohmann::json(chart_get_path()).dump();
    return chartPath.c_str();
}

DYCORE_API const char* DyCore_get_project_metadata() {
    static string projectMetadata;
    projectMetadata = project_get_metadata().dump();
    return projectMetadata.c_str();
}

DYCORE_API const char* DyCore_get_project_version() {
    static string projectVersion;
    projectVersion = project_get_version();
    return projectVersion.c_str();
}

DYCORE_API double DyCore_set_chart_metadata(const char* chartMetadataJson) {
    chart_set_metadata(nlohmann::json::parse(chartMetadataJson));
    return 0;
}

DYCORE_API double DyCore_set_chart_path(const char* chartPathJson) {
    chart_set_path(nlohmann::json::parse(chartPathJson));
    return 0;
}

DYCORE_API double DyCore_set_project_metadata(const char* projectMetadataJson) {
    project_set_metadata(nlohmann::json::parse(projectMetadataJson));
    return 0;
}

DYCORE_API double DyCore_set_project_version(const char* projectVersion) {
    project_set_version(projectVersion);
    return 0;
}

DYCORE_API double DyCore_load_chart_audio(const char* filePath) {
    return chart_load_audio(filePath);
}

// =============================================================================
// Difficulty-diff (multi-chart) APIs
// =============================================================================

DYCORE_API double DyCore_project_get_chart_count() {
    return static_cast<double>(ProjectManager::inst().get_chart_count());
}

DYCORE_API double DyCore_project_get_current_chart_index() {
    return static_cast<double>(ProjectManager::inst().get_current_chart_index());
}

DYCORE_API double DyCore_project_update_current_chart() {
    ProjectManager::inst().update_current_chart();
    return 0;
}

DYCORE_API double DyCore_project_set_current_chart(double index) {
    try {
        ProjectManager::inst().set_current_chart(static_cast<int>(index));
        return 0;
    } catch (const std::exception& e) {
        throw_error_event(e.what());
        return -1;
    }
}

DYCORE_API double DyCore_project_create_chart(double difficulty,
                                              double copyFromCurrent) {
    try {
        ProjectManager::inst().update_current_chart();
        const int idx = ProjectManager::inst().create_chart(
            static_cast<int>(difficulty), copyFromCurrent > 0);
        return static_cast<double>(idx);
    } catch (const std::exception& e) {
        throw_error_event(e.what());
        return -1;
    }
}

DYCORE_API double DyCore_project_delete_current_chart() {
    try {
        ProjectManager::inst().update_current_chart();
        return static_cast<double>(
            ProjectManager::inst().delete_current_chart());
    } catch (const std::exception& e) {
        throw_error_event(e.what());
        return -1;
    }
}

DYCORE_API double DyCore_project_find_chart_by_difficulty(double difficulty) {
    return static_cast<double>(
        ProjectManager::inst().find_chart_by_difficulty(
            static_cast<int>(difficulty)));
}

DYCORE_API const char* DyCore_project_get_chart_difficulties() {
    static string result;
    try {
        result = nlohmann::json(ProjectManager::inst().get_chart_difficulties())
                     .dump();
    } catch (const std::exception& e) {
        print_debug_message("Failed to get chart difficulties: " +
                            string(e.what()));
        result = "[]";
    }
    return result.c_str();
}

DYCORE_API const char* DyCore_project_get_diff_preview_notes(
    double difficulty, double timeMin, double timeMax, double excludeOverlap) {
    static string result;
    try {
        result = ProjectManager::inst().get_diff_preview_notes_json(
            static_cast<int>(difficulty), timeMin, timeMax,
            excludeOverlap > 0);
    } catch (const std::exception& e) {
        print_debug_message("Failed to get diff preview notes: " +
                            string(e.what()));
        result = "[]";
    }
    return result.c_str();
}

DYCORE_API double DyCore_project_export_current_as_single(const char* filePath,
                                                          double compressionLevel) {
    try {
        if (!filePath || strlen(filePath) == 0) {
            throw std::runtime_error("File path is empty.");
        }
        Project exportProject =
            ProjectManager::inst().create_single_chart_export_snapshot();
        const string projectString = nlohmann::json(exportProject).dump();
        if (projectString.empty()) {
            throw std::runtime_error("Empty single-chart project payload.");
        }

        auto buffer = std::make_unique<char[]>(
            compress_bound(projectString.size()));
        const double compressedSize = get_project_buffer(
            projectString, buffer.get(), compressionLevel);
        if (compressedSize < 0) {
            throw std::runtime_error("Error compressing project data.");
        }

        const auto path = convert_char_to_path(filePath);
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        if (!file.is_open()) {
            throw std::runtime_error("Failed to open export file for writing.");
        }
        file.write(buffer.get(), static_cast<std::streamsize>(compressedSize));
        file.close();
        if (file.fail()) {
            throw std::runtime_error("Failed to write export file.");
        }
        print_debug_message("Exported single-chart project to: " +
                            string(filePath));
        return 0;
    } catch (const std::exception& e) {
        print_debug_message("Failed to export single-chart project: " +
                            string(e.what()));
        throw_error_event(e.what());
        return -1;
    }
}
