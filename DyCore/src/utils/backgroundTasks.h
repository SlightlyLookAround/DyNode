#pragma once

#include <functional>

// Lightweight background thread tracker.
//
// Threads launched via `launch()` are stored in a shared pool. At shutdown,
// `join_all()` waits for every tracked task to finish, preventing the
// undefined behaviour that occurs when a detached thread is still running
// during DLL_PROCESS_DETACH.
//
// Finished threads are opportunistically reaped at the next `launch()` call
// to keep the pool from growing unboundedly.

namespace background_tasks {

// Launches a tracked background thread.
void launch(std::function<void()> func);

// Joins all tracked threads that have not yet been reaped. Safe to call
// multiple times. Blocks until every thread finishes.
void join_all();

}  // namespace background_tasks
