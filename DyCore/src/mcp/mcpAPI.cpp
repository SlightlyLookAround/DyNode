#include "api.h"

#include <string>

#include "json.hpp"
#include "mcpBridge.h"
#include "mcpServer.h"

namespace {

std::string stored;

const char* store(const nlohmann::json& j) {
    stored = j.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    return stored.c_str();
}

}  // namespace

// Start the embedded MCP HTTP server. port<=0 uses default 8765 with fallback.
DYCORE_API const char* DyCore_mcp_start(double port) {
    try {
        mcp::McpServer::Config config;
        if (port > 0) {
            config.preferredPort = static_cast<int>(port);
        }
        return store(mcp::McpServer::inst().start(config));
    } catch (const std::exception& e) {
        return store({{"ok", false}, {"error", e.what()}});
    } catch (...) {
        return store({{"ok", false}, {"error", "unknown error"}});
    }
}

DYCORE_API const char* DyCore_mcp_stop() {
    try {
        return store(mcp::McpServer::inst().stop());
    } catch (const std::exception& e) {
        return store({{"ok", false}, {"error", e.what()}});
    } catch (...) {
        return store({{"ok", false}, {"error", "unknown error"}});
    }
}

DYCORE_API double DyCore_mcp_is_running() {
    return mcp::McpServer::inst().is_running() ? 1.0 : 0.0;
}

DYCORE_API const char* DyCore_mcp_get_info() {
    try {
        return store(mcp::McpServer::inst().info());
    } catch (...) {
        return store({{"running", false}});
    }
}

// Drain pending main-thread jobs as a JSON array string.
DYCORE_API const char* DyCore_mcp_take_jobs() {
    try {
        nlohmann::json arr = nlohmann::json::array();
        for (const auto& job : mcp::McpBridge::inst().take_jobs(32)) {
            arr.push_back({{"requestId", job.requestId},
                           {"kind", job.kind},
                           {"payload", job.payload}});
        }
        return store(arr);
    } catch (...) {
        return store(nlohmann::json::array());
    }
}

// resultJson: {requestId, ok, result, error}
DYCORE_API double DyCore_mcp_complete(const char* resultJson) {
    if (resultJson == nullptr) return -1;
    try {
        auto parsed = nlohmann::json::parse(resultJson);
        const uint64_t requestId = parsed.value("requestId", static_cast<uint64_t>(0));
        const bool ok = parsed.value("ok", false);
        nlohmann::json result =
            parsed.contains("result") ? parsed["result"] : nlohmann::json::object();
        const std::string error = parsed.value("error", std::string{});
        mcp::McpBridge::inst().complete(requestId, ok, result, error);
        return 0;
    } catch (...) {
        return -1;
    }
}
