#pragma once

#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include "json.hpp"

namespace mcp {

struct ToolSpec {
    std::string name;
    std::string description;
    nlohmann::json inputSchema;
};

struct ToolOutcome {
    bool isError = false;
    nlohmann::json payload = nlohmann::json::object();
};

using ToolHandler = std::function<ToolOutcome(const nlohmann::json& arguments)>;

class McpToolRegistry {
   public:
    static McpToolRegistry& inst();

    void register_tool(ToolSpec spec, ToolHandler handler);
    std::vector<ToolSpec> list_tools() const;
    bool has_tool(const std::string& name) const;
    ToolOutcome call(const std::string& name, const nlohmann::json& arguments) const;
    void clear();

   private:
    struct Entry {
        ToolSpec spec;
        ToolHandler handler;
    };

    mutable std::mutex mtx;
    std::vector<Entry> tools;
};

// Registers the v1 tool surface (status / notes / timing / expression).
void register_default_tools();

// Static expression language catalog used by get_expression_reference.
nlohmann::json expression_reference_json();

}  // namespace mcp
