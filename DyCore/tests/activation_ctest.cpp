#include <doctest/doctest.h>

#include <cstring>
#include <string>
#include <vector>

#include "activation.h"
#include "bitio.h"
#include "note.h"
#include "notePoolManager.h"

extern "C" double DyCore_clear_notes();

namespace {

const char* parse_record(const char* buffer, size_t& bytesLeft, Note& out) {
    std::memcpy(&out.side, buffer, sizeof(int));
    std::memcpy(&out.type, buffer + sizeof(int), sizeof(int));
    const size_t fixed = sizeof(int) * 2 + sizeof(double) * 5;
    std::memcpy(&out.time, buffer + sizeof(int) * 2, sizeof(double));
    std::memcpy(&out.width, buffer + sizeof(int) * 2 + sizeof(double),
                sizeof(double));
    std::memcpy(&out.position,
                buffer + sizeof(int) * 2 + sizeof(double) * 2, sizeof(double));
    std::memcpy(&out.lastTime,
                buffer + sizeof(int) * 2 + sizeof(double) * 3, sizeof(double));
    std::memcpy(&out.beginTime,
                buffer + sizeof(int) * 2 + sizeof(double) * 4, sizeof(double));
    const char* strings = buffer + fixed;
    out.noteID = strings;
    strings += out.noteID.size() + 1;
    out.subNoteID = strings;
    strings += out.subNoteID.size() + 1;
    const size_t consumed = static_cast<size_t>(strings - buffer);
    REQUIRE(bytesLeft >= consumed);
    bytesLeft -= consumed;
    return strings;
}

}  // namespace

TEST_CASE("ActiveNotesPropsBatch") {
    DyCore_clear_notes();

    auto& pool = get_note_pool_manager();
    auto& man = get_note_activation_manager();

    // A normal note, a chain note and a hold (which creates its own sub-note).
    auto makeNote = [](double time, int side, int type) {
        Note note{};
        note.side = side;
        note.type = type;
        note.time = time;
        note.width = 1.5;
        note.position = 0.25 + time / 1000.0;
        note.lastTime = type == 2 ? 120.0 : 0.0;
        note.beginTime = time;
        return note;
    };
    REQUIRE(create_note(makeNote(100.0, 0, 0), true, false) == 0);
    REQUIRE(create_note(makeNote(200.0, 1, 1), true, false) == 0);
    REQUIRE(create_note(makeNote(300.0, 0, 2), true, true) == 0);

    man.set_range(0.0, 1.0);
    man.recalculate();

    const auto& active = man.get_active_notes();
    REQUIRE(active.size() >= 2);

    std::vector<char> buffer(man.get_active_notes_props_bound());
    REQUIRE(man.bitwrite_active_notes_props(buffer.data()));

    int count = 0;
    std::memcpy(&count, buffer.data(), sizeof(int));
    REQUIRE(count >= 3);  // 2 heads + 1 hold head; subs of holds are included.

    std::vector<Note> records;
    size_t bytesLeft = buffer.size() - sizeof(int);
    const char* ptr = buffer.data() + sizeof(int);
    for (int i = 0; i < count; i++) {
        Note record;
        ptr = parse_record(ptr, bytesLeft, record);
        records.push_back(record);
    }

    // Every record must exist in the pool with identical fields.
    for (const auto& record : records) {
        REQUIRE(pool.note_exists(record.noteID));
        const Note& expected = pool.get_note(record.noteID);
        CHECK(record.side == expected.side);
        CHECK(record.type == expected.type);
        CHECK(record.time == expected.time);
        CHECK(record.width == expected.width);
        CHECK(record.position == expected.position);
        CHECK(record.lastTime == expected.lastTime);
        CHECK(record.beginTime == expected.beginTime);
        CHECK(record.subNoteID == expected.subNoteID);
    }

    // The hold's sub-note must be part of the batch.
    bool foundSub = false;
    for (const auto& record : records) {
        if (record.type == static_cast<int>(NOTE_TYPE::HOLD) &&
            !record.subNoteID.empty()) {
            for (const auto& other : records) {
                if (other.noteID == record.subNoteID) {
                    foundSub = true;
                }
            }
        }
    }
    CHECK(foundSub);
}

TEST_CASE("ActiveNotesPropsBatchParallel") {
    DyCore_clear_notes();

    auto& man = get_note_activation_manager();

    // Enough notes to exceed the parallel serialization threshold.
    for (int i = 0; i < 300; i++) {
        Note note{};
        note.side = i % 3;
        note.type = 0;
        note.time = 100.0 + i;
        note.width = 1.0;
        note.position = 0.5;
        note.lastTime = 0.0;
        note.beginTime = note.time;
        REQUIRE(create_note(note, true, false) == 0);
    }

    man.set_range(0.0, 1.0);
    man.recalculate();

    const auto& active = man.get_active_notes();
    REQUIRE(active.size() == 300);

    std::vector<char> buffer(man.get_active_notes_props_bound());
    REQUIRE(man.bitwrite_active_notes_props(buffer.data()));

    int count = 0;
    std::memcpy(&count, buffer.data(), sizeof(int));
    CHECK(count == 300);

    // All IDs in the batch must match the active list (order preserved).
    size_t bytesLeft = buffer.size() - sizeof(int);
    const char* ptr = buffer.data() + sizeof(int);
    for (int i = 0; i < count; i++) {
        Note record;
        ptr = parse_record(ptr, bytesLeft, record);
        CHECK(record.noteID == active[static_cast<size_t>(i)].second);
    }
}
