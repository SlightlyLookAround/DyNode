#include <doctest/doctest.h>

#include <httplib/httplib.h>

#include <chrono>
#include <thread>

#include "json.hpp"
#include "mcp/mcpBridge.h"
#include "mcp/mcpProtocol.h"
#include "mcp/mcpServer.h"
#include "mcp/mcpTools.h"
#include "note.h"
#include "notePoolManager.h"
#include "timing.h"

using nlohmann::json;

TEST_CASE("mcp http transport initialize + tools/call over localhost") {
    clear_notes();
    get_timing_manager().clear();
    mcp::reset_protocol_state_for_tests();
    mcp::register_default_tools();
    mcp::McpBridge::inst().cancel_all("reset");

    mcp::McpServer::Config config;
    config.preferredPort = 18765;
    config.portFallbackCount = 20;
    config.requireToken = true;
    config.token = "test-token";

    auto started = mcp::McpServer::inst().start(config);
    REQUIRE(started.value("ok", false));
    const std::string token = started.at("token").get<std::string>();
    const int port = started.at("port").get<int>();
    REQUIRE(token == "test-token");

    httplib::Client client("127.0.0.1", port);
    client.set_read_timeout(5, 0);
    client.set_bearer_token_auth(token);

    // Unauthorized without token
    {
        httplib::Client bare("127.0.0.1", port);
        auto bad = bare.Post("/mcp", "{}", "application/json");
        REQUIRE(bad);
        CHECK(bad->status == 401);
    }

    // initialize
    json init = {{"jsonrpc", "2.0"},
                 {"id", 1},
                 {"method", "initialize"},
                 {"params",
                  {{"protocolVersion", "2025-06-18"},
                   {"clientInfo", {{"name", "http-test"}}},
                   {"capabilities", json::object()}}}};
    auto initRes = client.Post("/mcp", init.dump(), "application/json");
    REQUIRE(initRes);
    CHECK(initRes->status == 200);
    REQUIRE(initRes->has_header("Mcp-Session-Id"));
    const std::string sessionId = initRes->get_header_value("Mcp-Session-Id");
    auto initBody = json::parse(initRes->body);
    REQUIRE(initBody.contains("result"));
    CHECK(initBody["result"]["serverInfo"]["name"] == "dynode");

    // notifications/initialized
    json note = {{"jsonrpc", "2.0"}, {"method", "notifications/initialized"}};
    httplib::Headers headers{{"Mcp-Session-Id", sessionId}};
    auto noteRes = client.Post("/mcp", headers, note.dump(), "application/json");
    REQUIRE(noteRes);
    CHECK(noteRes->status == 202);

    // tools/call insert_notes
    json call = {{"jsonrpc", "2.0"},
                 {"id", 2},
                 {"method", "tools/call"},
                 {"params",
                  {{"name", "insert_notes"},
                   {"arguments",
                    {{"notes",
                      json::array({{{"side", 0},
                                    {"type", 0},
                                    {"time", 250.0},
                                    {"width", 1.0},
                                    {"position", 1.5}}})}}}}}};
    auto callRes = client.Post("/mcp", headers, call.dump(), "application/json");
    REQUIRE(callRes);
    CHECK(callRes->status == 200);
    auto callBody = json::parse(callRes->body);
    REQUIRE(callBody.contains("result"));
    CHECK(callBody["result"]["isError"] == false);
    CHECK(get_note_pool_manager().get_note_count() >= 1);

    // health endpoint
    auto health = client.Get("/health", headers);
    REQUIRE(health);
    CHECK(health->status == 200);

    auto stopped = mcp::McpServer::inst().stop();
    CHECK(stopped.value("ok", false));
    CHECK_FALSE(mcp::McpServer::inst().is_running());
}
