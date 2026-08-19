#include "notePoolManager.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <mutex>
#include <random>
#include <shared_mutex>
#include <stdexcept>
#include <taskflow/algorithm/for_each.hpp>
#include <taskflow/algorithm/sort.hpp>
#include <taskflow/taskflow.hpp>
#include <thread>
#include <unordered_set>
#include <vector>
#include <xxhash/xxhash.h>

#include "bitio.h"
#include "note.h"
#include "notePoolManager.h"
#include "profile.h"
#include "taskflow/core/executor.hpp"
#include "utils.h"

tf::Executor &get_shared_taskflow_executor() {
    static tf::Executor executor(static_cast<size_t>(std::max(
        static_cast<unsigned int>(1), std::thread::hardware_concurrency())));
    return executor;
}

NotePoolManager::NotePoolManager()
    : monotonic_res(initial_buffer.data(), initial_buffer.size(),
                    std::pmr::new_delete_resource()),
      pool_res(&monotonic_res),
      arrayOutOfOrder(false) {
}

NotePoolManager::~NotePoolManager() {
}

const Note& NotePoolManager::operator[](int index) {
    std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
    if (index < 0 || index >= noteArray.size())
        throw std::out_of_range(
            "Index out of range in NotePoolManager. Range: " +
            std::to_string(noteArray.size()) +
            ", requested: " + std::to_string(index));
    if (arrayOutOfOrder)
        throw std::runtime_error(
            "Note array is out of order. Use get_note_direct() instead.");

    return *noteArray[index];
}

bool NotePoolManager::note_exists(const std::string& noteID) {
    return noteInfoMap.find(noteID) != noteInfoMap.end();
}

bool NotePoolManager::create_note(const Note& note) {
    std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
    if (note_exists(note.noteID)) {
        return false;
    }
    try {
        std::pmr::polymorphic_allocator<Note> alloc(&pool_res);
        auto ptr = std::allocate_shared<Note>(alloc);

        *ptr = note;

        noteMemoryList.emplace_back(ptr);
        noteInfoMap[note.noteID] = {--noteMemoryList.end(), ptr,
                                    static_cast<int>(noteArray.size()),
                                    note.get_note_type() == NOTE_TYPE::HOLD
                                        ? static_cast<int>(holdArray.size())
                                        : -1};

        noteArray.push_back(ptr);
        if (note.get_note_type() == NOTE_TYPE::HOLD)
            holdArray.push_back(ptr);

        set_ooo();
        noteCount++;

        return true;
    } catch (const std::bad_alloc& e) {
        print_debug_message("Failed to create note: " + std::string(e.what()));
        return false;
    }
}

const Note& NotePoolManager::get_note(const std::string& noteID) {
    nptr note_ptr;
    {
        std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
        if (noteInfoMap.find(noteID) == noteInfoMap.end()) {
            throw std::runtime_error("Note not found: " + noteID);
        }
        note_ptr = get_note_pointer(noteID);
    }  // Release the manager lock

    return *note_ptr;
}

void NotePoolManager::get_notes(std::vector<Note>& outNotes,
                                bool excludeSub) const {
    std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
    outNotes.clear();
    for (const auto& note_ptr : noteArray) {
        if (note_ptr) {
            if (excludeSub && note_ptr->get_note_type() == NOTE_TYPE::SUB) {
                continue;  // Skip sub notes
            }
            outNotes.push_back(*note_ptr);
        }
    }
}

const Note& NotePoolManager::get_note_direct(int index) {
    std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
    if (index < 0 || index >= static_cast<int>(noteArray.size())) {
        throw std::out_of_range("Index out of range in NotePoolManager");
    }
    return *noteArray[index];
}

void NotePoolManager::set_note(const Note& note) {
    nptr note_ptr;
    {
        std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
        if (noteInfoMap.find(note.noteID) == noteInfoMap.end()) {
            throw std::runtime_error("Note not found: " + note.noteID);
        }
        note_ptr = get_note_pointer(note.noteID);
    }  // Release the manager lock
    if (note_ptr->time != note.time)
        set_ooo();
    *note_ptr = note;

    sync_head_note_to_sub(*note_ptr);
    sync_hold_note_length(*note_ptr);
}

void NotePoolManager::set_note_bitwise(const char* prop) {
    Note note;
    note.read(prop);
    set_note(note);
}

void NotePoolManager::access_note(const std::string& noteID,
                                  std::function<void(Note&)> executor) {
    nptr note_ptr;
    {
        std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
        if (noteInfoMap.find(noteID) == noteInfoMap.end()) {
            throw std::runtime_error("Note not found: " + noteID);
        }
        note_ptr = get_note_pointer(noteID);
    }  // Release the manager lock

    double origTime = note_ptr->time;
    executor(*note_ptr);
    if (origTime != note_ptr->time)
        set_ooo();
    sync_head_note_to_sub(*note_ptr);
    sync_hold_note_length(*note_ptr);
}

// This function is unsafe (DEADLOCK RISK). Do not access notePoolManager in
// your executor.
void NotePoolManager::access_all_notes(std::function<void(Note&)> executor) {
    std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
    for (const auto& note_ptr : noteArray) {
        if (note_ptr) {
            double origTime = note_ptr->time;
            executor(*note_ptr);
            if (origTime != note_ptr->time)
                set_ooo();
            sync_head_note_to_sub(*note_ptr);
            sync_hold_note_length(*note_ptr);
        }
    }
}

// This function is slower (but safer)
void NotePoolManager::access_all_notes_safe(
    std::function<void(Note&)> executor) {
    std::vector<nptr> notes;
    {
        std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
        notes.reserve(get_note_count());
        for (const auto& note_ptr : noteArray) {
            if (note_ptr) {
                notes.push_back(note_ptr);
            }
        }
    }
    for (const auto& note_ptr : notes) {
        double origTime = note_ptr->time;
        executor(*note_ptr);
        if (origTime != note_ptr->time)
            set_ooo();
        sync_head_note_to_sub(*note_ptr);
        sync_hold_note_length(*note_ptr);
    }
}

// This function is unsafe (DEADLOCK RISK). Do not access notePoolManager in
// your executor.
void NotePoolManager::access_all_notes_parallel(
    std::function<void(Note&)> executor) {
    std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
    tf::Taskflow taskflow;
    taskflow.for_each(noteArray.begin(), noteArray.end(), [&](nptr note_ptr) {
        if (note_ptr) {
            double origTime = note_ptr->time;
            executor(*note_ptr);
            if (origTime != note_ptr->time)
                set_ooo();
            sync_head_note_to_sub(*note_ptr);
            sync_hold_note_length(*note_ptr);
        }
    });
    get_shared_taskflow_executor().run(taskflow).wait();
}

void NotePoolManager::access_all_notes_parallel_safe(
    std::function<void(Note&)> executor) {
    std::vector<nptr> notes;
    {
        std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
        notes.reserve(get_note_count());
        for (const auto& note_ptr : noteArray) {
            if (note_ptr) {
                notes.push_back(note_ptr);
            }
        }
    }
    tf::Taskflow taskflow;
    taskflow.for_each(notes.begin(), notes.end(), [&](nptr note_ptr) {
        double origTime = note_ptr->time;
        executor(*note_ptr);
        if (origTime != note_ptr->time)
            set_ooo();
        sync_head_note_to_sub(*note_ptr);
        sync_hold_note_length(*note_ptr);
    });
    get_shared_taskflow_executor().run(taskflow).wait();
}

void NotePoolManager::sync_head_note_to_sub(const Note& note) {
    if (note.get_note_type() != NOTE_TYPE::HOLD)
        return;
    auto subNote = get_note_pointer(note.subNoteID);
    if (subNote) {
        subNote->beginTime = note.time;
        subNote->position = note.position;
        subNote->width = note.width;
        subNote->side = note.side;
    }
}

void NotePoolManager::sync_hold_note_length(const Note& note) {
    if (note.get_note_type() != NOTE_TYPE::HOLD &&
        note.get_note_type() != NOTE_TYPE::SUB)
        return;
    nptr holdNote = get_note_pointer(note.noteID);
    nptr subNote = get_note_pointer(note.subNoteID);
    if (holdNote->get_note_type() == NOTE_TYPE::SUB)
        std::swap(holdNote, subNote);
    holdNote->lastTime = subNote->time - holdNote->time;
}

void NotePoolManager::clear_notes() {
    std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
    noteArray.clear();
    noteArray.shrink_to_fit();
    holdArray.clear();
    holdArray.shrink_to_fit();
    noteMemoryList.clear();
    noteInfoMap.clear();
    // In C++20, there's no shrink_to_fit for unordered_map,
    // but rehash(0) can help reduce bucket count.
    noteInfoMap.rehash(0);

    noteCount = 0;
    get_note_activation_manager().clear();
    reclaim_memory();
    return;
}

int NotePoolManager::get_index(const std::string& noteID) {
    std::shared_lock<std::shared_mutex> lock(mtxNoteOps);

    if (arrayOutOfOrder) {
        throw std::runtime_error(
            "Note array is out of order, cannot get index directly.");
    }

    auto it = noteInfoMap.find(noteID);
    if (it == noteInfoMap.end()) {
        throw std::runtime_error("Note not found: " + noteID);
    }
    return it->second.index;
}

bool NotePoolManager::release_note(std::string noteID) {
    std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
    auto it = noteInfoMap.find(noteID);
    if (it == noteInfoMap.end()) {
        return false;
    }

    auto info = it->second;

    array_markdel_index(info);
    noteMemoryList.erase(info.iter);
    noteInfoMap.erase(it);

    set_ooo();
    noteCount--;
    return true;
}

bool NotePoolManager::release_note(const Note& note) {
    return release_note(note.noteID);
}

bool NotePoolManager::array_sort_request() {
    std::lock_guard<std::shared_mutex> lock(mtxNoteOps);
    if (!arrayOutOfOrder) {
        return false;
    }

    array_sort();
    unset_ooo();
    return true;
}

void NotePoolManager::set_ooo() {
    arrayOutOfOrder = true;
}

void NotePoolManager::unset_ooo() {
    arrayOutOfOrder = false;
}

void NotePoolManager::array_markdel_index(const NoteMemoryInfo& info) {
    noteArray[info.index] = nullptr;
    if (info.holdIndex >= 0) {
        holdArray[info.holdIndex] = nullptr;
    }
    set_ooo();
}

// Should only be called when mtxNoteOps is locked
void NotePoolManager::array_sort() {
    PROFILE_SCOPE("Note Pool Manager Array Sort");
    static auto noteArray_cmp = [](const nptr& a, const nptr& b) {
        if (a == nullptr)
            return false;
        if (b == nullptr)
            return true;
        return a->time < b->time;
    };
    static auto holdArray_cmp = [](const nptr& a, const nptr& b) {
        if (a == nullptr)
            return false;
        if (b == nullptr)
            return true;
        return a->lastTime > b->lastTime;
    };

    auto single_array_pop = [&](std::vector<nptr>& array) {
        while (!array.empty() && array.back() == nullptr) {
            array.pop_back();
        }
    };

    auto start = std::chrono::high_resolution_clock::now();
    bool enableParallelSort;
    enableParallelSort =
        noteArray.size() >= NOTES_ARRAY_PARALLEL_SORT_THRESHOLD &&
        hardware_concurrency() > 1;
    if (enableParallelSort) {
        // Use parallel sort
        tf::Taskflow taskflow;
        taskflow.sort(noteArray.begin(), noteArray.end(), noteArray_cmp);
        taskflow.sort(holdArray.begin(), holdArray.end(), holdArray_cmp);
        get_shared_taskflow_executor().run(taskflow).wait();
    } else {
        std::sort(noteArray.begin(), noteArray.end(), noteArray_cmp);
        std::sort(holdArray.begin(), holdArray.end(), holdArray_cmp);
    }

    single_array_pop(noteArray);
    single_array_pop(holdArray);

    for (size_t i = 0; i < noteArray.size(); ++i) {
        noteInfoMap[noteArray[i]->noteID].index = i;
    }
    for (size_t i = 0; i < holdArray.size(); ++i) {
        noteInfoMap[holdArray[i]->noteID].holdIndex = i;
    }
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration<double, std::milli>(end - start);
    print_debug_message("array_sort took " + std::to_string(duration.count()) +
                        "ms");
}

NotePoolManager::nptr NotePoolManager::get_note_pointer(
    const std::string& noteID) {
    // Should only be called when mtxNoteOps is locked
    return noteInfoMap.find(noteID)->second.pointer;
}

int NotePoolManager::get_index_upperbound(double time) {
    std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
    if (arrayOutOfOrder)
        throw std::runtime_error(
            "Note array is out of order, cannot get index directly.");

    auto it = std::upper_bound(
        noteArray.begin(), noteArray.end(), time,
        [](double t, const nptr& note) { return t < note->time; });
    if (it == noteArray.end()) {
        return static_cast<int>(noteArray.size());
    }
    return static_cast<int>(it - noteArray.begin());
}

int NotePoolManager::get_index_lowerbound(double time) {
    std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
    if (arrayOutOfOrder)
        throw std::runtime_error(
            "Note array is out of order, cannot get index directly.");

    auto it = std::lower_bound(
        noteArray.begin(), noteArray.end(), time,
        [](const nptr& note, double t) { return note->time < t; });
    if (it == noteArray.end()) {
        return static_cast<int>(noteArray.size());
    }
    return static_cast<int>(it - noteArray.begin());
}

// Thread unsafe function.
void NotePoolManager::reclaim_memory() {
    pool_res.release();
    monotonic_res.release();
}

// ---------------------------------------------------------------------------
// Batch operations — parallel processing via shared taskflow executor.
// ---------------------------------------------------------------------------

static constexpr double BASE_RES_W = 1920.0;
static constexpr double BASE_RES_H = 1080.0;

static double note_pos_to_x_cxx(double position, int side) {
    if (side == 0)
        return BASE_RES_W / 2.0 + (position - 2.5) * 300.0;
    return BASE_RES_H / 2.0 + (2.5 - position) * 150.0;
}

static double get_pixel_width_cxx(double width, int side) {
    double pWidth = width * 300.0 / (side == 0 ? 1.0 : 2.0) - 30.0;
    return std::max(pWidth, 0.0);
}

static bool is_outscreen_cxx(double position, double width, int side) {
    double pWidth = get_pixel_width_cxx(width, side);
    double nx = note_pos_to_x_cxx(position, side);
    if (side == 0) {
        double xl = nx - pWidth / 2.0;
        double xr = nx + pWidth / 2.0;
        return xr <= 0.0 || xl >= BASE_RES_W;
    }
    double yl = nx - pWidth / 2.0;
    double yr = nx + pWidth / 2.0;
    return yr <= 0.0 || yl >= BASE_RES_H;
}

int NotePoolManager::batch_fix_notes() {
    array_sort_request();

    std::vector<nptr> notes;
    {
        std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
        notes.reserve(noteArray.size());
        for (const auto& ptr : noteArray) {
            if (ptr)
                notes.push_back(ptr);
        }
    }

    std::atomic<int> fixCount{0};

    tf::Taskflow taskflow;
    taskflow.for_each(notes.begin(), notes.end(), [&](const nptr& notePtr) {
        if (notePtr->type == static_cast<int>(NOTE_TYPE::SUB))
            return;
        if (!is_outscreen_cxx(notePtr->position, notePtr->width, notePtr->side))
            return;
        double clamped = std::clamp(notePtr->position, 0.0, 5.0);
        if (clamped != notePtr->position) {
            notePtr->position = clamped;
            fixCount.fetch_add(1, std::memory_order_relaxed);
        }
    });
    get_shared_taskflow_executor().run(taskflow).wait();

    if (fixCount.load() > 0)
        set_ooo();

    return fixCount.load();
}

int NotePoolManager::batch_timing_fix(double tpBeforeTime,
                                      double tpBeforeBeatLen,
                                      double tpAfterTime,
                                      double tpAfterBeatLen,
                                      double nextTPTime,
                                      bool& crossWarning) {
    array_sort_request();

    const double timeL = tpBeforeTime;
    const double timeR = (nextTPTime < 0) ? 1e9 : (nextTPTime - 1.0);

    int lo = get_index_lowerbound(timeL);
    int hi = get_index_upperbound(timeR);
    if (lo >= hi)
        return 0;

    std::vector<nptr> affected;
    {
        std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
        affected.reserve(hi - lo);
        for (int i = lo; i < hi; i++) {
            if (noteArray[i])
                affected.push_back(noteArray[i]);
        }
    }

    if (affected.empty())
        return 0;

    const double ratio = tpAfterBeatLen / tpBeforeBeatLen;
    std::atomic<int> affectedCount{0};
    std::atomic<bool> cross{false};

    tf::Taskflow taskflow;
    taskflow.for_each(affected.begin(), affected.end(), [&](const nptr& notePtr) {
        if (notePtr->type == static_cast<int>(NOTE_TYPE::SUB))
            return;
        double newTime = (notePtr->time - tpBeforeTime) * ratio + tpAfterTime;
        if (newTime > timeR)
            cross.store(true, std::memory_order_relaxed);
        if (notePtr->type == static_cast<int>(NOTE_TYPE::HOLD))
            notePtr->lastTime *= ratio;
        notePtr->time = newTime;
        affectedCount.fetch_add(1, std::memory_order_relaxed);
    });
    get_shared_taskflow_executor().run(taskflow).wait();

    crossWarning = cross.load();

    if (affectedCount.load() > 0)
        set_ooo();

    return affectedCount.load();
}

int NotePoolManager::batch_randomize(char* outBuffer) {
    array_sort_request();

    struct NoteSnapshot {
        nptr ptr;
        std::string noteID;
        double origPosition;
        double origWidth;
        int origSide;
    };

    std::vector<NoteSnapshot> snapshots;
    {
        std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
        for (const auto& ptr : noteArray) {
            if (ptr && ptr->type != static_cast<int>(NOTE_TYPE::SUB)) {
                snapshots.push_back(
                    {ptr, ptr->noteID, ptr->position, ptr->width, ptr->side});
            }
        }
    }

    if (snapshots.empty()) {
        uint32_t zero = 0;
        std::memcpy(outBuffer, &zero, sizeof(uint32_t));
        return 0;
    }

    tf::Taskflow taskflow;
    taskflow.for_each_index(
        size_t{0}, snapshots.size(), size_t{1}, [&](size_t i) {
            thread_local std::mt19937 rng(std::random_device{}());
            std::uniform_real_distribution<double> posDist(0.0, 5.0);
            std::uniform_int_distribution<int> sideDist(0, 2);
            std::uniform_real_distribution<double> widthDist(0.5, 5.0);

            auto& snap = snapshots[i];
            snap.ptr->position = posDist(rng);
            snap.ptr->side = sideDist(rng);
            snap.ptr->width = widthDist(rng);
        });
    get_shared_taskflow_executor().run(taskflow).wait();

    set_ooo();

    // Write original props to output buffer for GML undo.
    char* writePtr = outBuffer;
    uint32_t snapCount = static_cast<uint32_t>(snapshots.size());
    std::memcpy(writePtr, &snapCount, sizeof(uint32_t));
    writePtr += sizeof(uint32_t);

    for (const auto& snap : snapshots) {
        std::memcpy(writePtr, snap.noteID.c_str(), snap.noteID.size() + 1);
        writePtr += snap.noteID.size() + 1;
        bitwrite(writePtr, snap.origSide);
        bitwrite(writePtr, snap.origWidth);
        bitwrite(writePtr, snap.origPosition);
    }

    return static_cast<int>(snapshots.size());
}

std::string NotePoolManager::batch_find_duplicates() {
    static std::string resultJson;

    array_sort_request();

    const int count = get_note_count();
    if (count <= 0) {
        resultJson = "[]";
        return resultJson;
    }

    struct NoteInfo {
        std::string noteID;
        XXH64_hash_t hash;
    };

    std::vector<NoteInfo> infos;
    {
        std::shared_lock<std::shared_mutex> lock(mtxNoteOps);
        for (const auto& ptr : noteArray) {
            if (ptr && ptr->type != static_cast<int>(NOTE_TYPE::SUB)) {
                infos.push_back({ptr->noteID, ptr->get_hash(false)});
            }
        }
    }

    if (infos.empty()) {
        resultJson = "[]";
        return resultJson;
    }

    std::unordered_set<XXH64_hash_t> seen;
    std::vector<std::string> duplicateIDs;
    seen.reserve(infos.size());

    for (const auto& info : infos) {
        if (!seen.insert(info.hash).second) {
            duplicateIDs.push_back(info.noteID);
        }
    }

    resultJson = "[";
    for (size_t i = 0; i < duplicateIDs.size(); i++) {
        if (i > 0)
            resultJson += ",";
        resultJson += "\"" + duplicateIDs[i] + "\"";
    }
    resultJson += "]";

    return resultJson;
}

// Singleton getter.
NotePoolManager& get_note_pool_manager() {
    static NotePoolManager instance;
    return instance;
}
