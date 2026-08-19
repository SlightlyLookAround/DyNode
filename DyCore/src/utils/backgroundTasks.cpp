#include "backgroundTasks.h"

#include <mutex>
#include <thread>
#include <vector>

namespace background_tasks {

static std::mutex s_mutex;
static std::vector<std::thread> s_threads;

void launch(std::function<void()> func) {
    std::thread t(std::move(func));

    std::lock_guard<std::mutex> lock(s_mutex);
    s_threads.push_back(std::move(t));
}

void join_all() {
    std::lock_guard<std::mutex> lock(s_mutex);
    for (auto& t : s_threads) {
        if (t.joinable()) {
            t.join();
        }
    }
    s_threads.clear();
}

}  // namespace background_tasks
