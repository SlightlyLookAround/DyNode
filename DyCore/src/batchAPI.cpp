#include "api.h"
#include "notePoolManager.h"

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
