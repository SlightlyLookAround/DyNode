#pragma once

#include <memory>
#include <mutex>
#include <string>

#include "json.hpp"

namespace mcp {

// Streamable HTTP MCP server bound to 127.0.0.1. Thread-safe singleton.
class McpServer {
   public:
    struct Config {
        int preferredPort = 8765;
        int portFallbackCount = 11;
        bool requireToken = true;
        std::string token;  // generated when empty && requireToken
    };

    static McpServer& inst();

    // Returns {ok, url, port, token, host} or {ok:false, error}.
    nlohmann::json start(const Config& config);
    nlohmann::json start();
    nlohmann::json stop();
    nlohmann::json info() const;
    bool is_running() const;

   private:
    struct Impl;

    McpServer() = default;
    ~McpServer();

    mutable std::recursive_mutex mtx;
    std::unique_ptr<Impl> impl;
};

}  // namespace mcp
