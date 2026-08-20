#pragma once

#include <xxhash/xxhash.h>

#include <string>

#include "bitio.h"

inline constexpr int NOTE_ID_LENGTH = 9;

using std::string;

struct Note;
struct NoteExportView;

bool note_exists(const Note &note);
bool note_exists(const char *noteID);
bool note_exists(const string &noteID);
void clear_notes();
int insert_note(const Note &note);
int create_note(const Note &note, bool randomID = true, bool createSub = true);
int delete_note(const Note &note);
int delete_note(const std::string &noteID);
int modify_note(const Note &note);
int modify_note(const char *prop);

string generate_note_id();

void get_notes_array(std::vector<Note> &notes, bool excludeSub = true);
void get_notes_array(std::vector<NoteExportView> &notes,
                     bool excludeSub = true);
std::string get_notes_array_string();

enum class NOTE_TYPE { NORMAL, CHAIN, HOLD, SUB };

struct Note {
   public:
    int side;
    int type;
    double time;
    double width;
    double position;
    double lastTime;
    double beginTime;
    string noteID;
    string subNoteID;

    size_t bitsize() {
        return sizeof(int) * 2 + sizeof(double) * 5 +
               sizeof(char) * (noteID.size() + subNoteID.size() + 4);
    }

    void write(char *buffer) const {
        char *ptr = buffer;
        bitwrite(ptr, side);
        bitwrite(ptr, type);
        bitwrite(ptr, time);
        bitwrite(ptr, width);
        bitwrite(ptr, position);
        bitwrite(ptr, lastTime);
        bitwrite(ptr, beginTime);
        bitwrite(ptr, noteID);
        bitwrite(ptr, subNoteID);
    }

    void read(const char *&buffer) {
        const char *ptr = buffer;
        bitread(ptr, side);
        bitread(ptr, type);
        bitread(ptr, time);
        bitread(ptr, width);
        bitread(ptr, position);
        bitread(ptr, lastTime);
        bitread(ptr, beginTime);
        bitread(ptr, noteID);
        bitread(ptr, subNoteID);
    }

    NOTE_TYPE get_note_type() const {
        return static_cast<NOTE_TYPE>(type);
    }

    /**
     * Generates a 64-bit hash of the note's properties.
     * @param includeID Whether to include unique identifiers in the hash.
     * @return The calculated XXH64 hash.
     */
    XXH64_hash_t get_hash(bool includeID = false) const;

    /**
     * Generates a string representation of the note's hash.
     * @param includeID Whether to include unique identifiers in the hash.
     * @return The hash as a string.
     */
    std::string get_hash_string(bool includeID = false) const {
        XXH64_hash_t hash = get_hash(includeID);
        return std::to_string(hash);
    }
};

struct NoteExportView {
    const Note &note;
    NoteExportView(const Note &n) : note(n) {
    }
};
