#include <doctest/doctest.h>

#include <chrono>
#include <thread>

#include "json.hpp"
#include "mcp/mcpBridge.h"
#include "mcp/mcpProtocol.h"
#include "mcp/mcpTools.h"
#include "note.h"
#include "notePoolManager.h"
#include "timing.h"

using nlohmann::json;

namespace {

void reset_world() {
    clear_notes();
    get_timing_manager().clear();
    mcp::reset_protocol_state_for_tests();
    mcp::register_default_tools();
    mcp::McpBridge::inst().cancel_all("reset");
}

json initialize_session() {
    json req = {{"jsonrpc", "2.0"},
                {"id", 1},
                {"method", "initialize"},
                {"params",
                 {{"protocolVersion", "2025-06-18"},
                  {"clientInfo", {{"name", "doctest"}}},
                  {"capabilities", json::object()}}}};
    auto resp = mcp::handle_message(req.dump(), std::nullopt);
    REQUIRE(resp.httpStatus == 200);
    REQUIRE(resp.hasSessionHeader);
    REQUIRE(!resp.sessionId.empty());
    auto body = json::parse(resp.body);
    REQUIRE(body.contains("result"));
    return resp.sessionId;
}

json rpc(const std::string& sessionId, const json& msg) {
    auto resp = mcp::handle_message(msg.dump(), sessionId);
    REQUIRE(resp.httpStatus == 200);
    REQUIRE(!resp.body.empty());
    return json::parse(resp.body);
}

}  // namespace

TEST_CASE("mcp protocol initialize creates session and negotiates version") {
    reset_world();
    auto sessionId = initialize_session();
    CHECK(mcp::mcp_session_count() == 1);

    json initOld = {{"jsonrpc", "2.0"},
                    {"id", 9},
                    {"method", "initialize"},
                    {"params",
                     {{"protocolVersion", "1999-01-01"},
                      {"clientInfo", {{"name", "old"}}},
                      {"capabilities", json::object()}}}};
    auto resp = mcp::handle_message(initOld.dump(), std::nullopt);
    auto body = json::parse(resp.body);
    CHECK(body["result"]["protocolVersion"] == "2025-03-26");
}

TEST_CASE("mcp protocol rejects invalid session and unknown method") {
    reset_world();
    auto sessionId = initialize_session();

    json tools = {{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/list"}};
    auto missing = mcp::handle_message(tools.dump(), std::nullopt);
    auto missingBody = json::parse(missing.body);
    CHECK(missingBody["error"]["code"] == -32000);

    json bogus = {{"jsonrpc", "2.0"}, {"id", 3}, {"method", "nope/nope"}};
    auto bad = rpc(sessionId, bogus);
    CHECK(bad["error"]["code"] == -32601);
}

TEST_CASE("mcp protocol parse error and notification") {
    reset_world();
    auto broken = mcp::handle_message("{not json", std::nullopt);
    auto body = json::parse(broken.body);
    CHECK(body["error"]["code"] == -32700);

    auto sessionId = initialize_session();
    json note = {{"jsonrpc", "2.0"}, {"method", "notifications/initialized"}};
    auto resp = mcp::handle_message(note.dump(), sessionId);
    CHECK(resp.httpStatus == 202);
    CHECK(resp.body.empty());
}

TEST_CASE("mcp tools list and native note/timing roundtrip") {
    reset_world();
    auto sessionId = initialize_session();

    json list = {{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/list"}};
    auto listBody = rpc(sessionId, list);
    REQUIRE(listBody["result"]["tools"].is_array());
    CHECK(listBody["result"]["tools"].size() >= 8);

    json insert = {{"jsonrpc", "2.0"},
                   {"id", 3},
                   {"method", "tools/call"},
                   {"params",
                    {{"name", "insert_notes"},
                     {"arguments",
                      {{"notes",
                        json::array({{{"side", 0},
                                      {"type", 0},
                                      {"time", 1000.0},
                                      {"width", 1.0},
                                      {"position", 2.5}}})}}}}}};
    auto insertBody = rpc(sessionId, insert);
    REQUIRE(insertBody["result"]["isError"] == false);
    auto payload = json::parse(insertBody["result"]["content"][0]["text"].get<std::string>());
    CHECK(payload["count"] == 1);
    CHECK(get_note_pool_manager().get_note_count() >= 1);

    json listNotes = {{"jsonrpc", "2.0"},
                      {"id", 4},
                      {"method", "tools/call"},
                      {"params", {{"name", "list_notes"}, {"arguments", json::object()}}}};
    auto listNotesBody = rpc(sessionId, listNotes);
    auto notesPayload =
        json::parse(listNotesBody["result"]["content"][0]["text"].get<std::string>());
    CHECK(notesPayload["total"].get<int>() >= 1);

    json setTp = {{"jsonrpc", "2.0"},
                  {"id", 5},
                  {"method", "tools/call"},
                  {"params",
                   {{"name", "set_timing_points"},
                    {"arguments",
                     {{"mode", "replace"},
                      {"timingPoints",
                       json::array({{{"time", 0.0}, {"bpm", 120.0}, {"meter", 4}}})}}}}}};
    auto setTpBody = rpc(sessionId, setTp);
    CHECK(setTpBody["result"]["isError"] == false);
    CHECK(get_timing_manager().count() == 1);

    json exprRef = {{"jsonrpc", "2.0"},
                    {"id", 6},
                    {"method", "tools/call"},
                    {"params",
                     {{"name", "get_expression_reference"},
                      {"arguments", json::object()}}}};
    auto exprRefBody = rpc(sessionId, exprRef);
    auto ref = json::parse(exprRefBody["result"]["content"][0]["text"].get<std::string>());
    CHECK(ref.contains("variables"));
    CHECK(ref.contains("functions"));
}

TEST_CASE("mcp delete_notes requires confirm for filter") {
    reset_world();
    auto sessionId = initialize_session();
    json insert = {{"jsonrpc", "2.0"},
                   {"id", 1},
                   {"method", "tools/call"},
                   {"params",
                    {{"name", "insert_notes"},
                     {"arguments",
                      {{"notes",
                        json::array({{{"side", 0},
                                      {"type", 0},
                                      {"time", 500.0},
                                      {"width", 1.0},
                                      {"position", 1.0}}})}}}}}};
    rpc(sessionId, insert);

    json del = {{"jsonrpc", "2.0"},
                {"id", 2},
                {"method", "tools/call"},
                {"params",
                 {{"name", "delete_notes"},
                  {"arguments", {{"filter", {{"timeMin", 0}, {"timeMax", 1000}}}}}}}};
    auto delBody = rpc(sessionId, del);
    CHECK(delBody["result"]["isError"] == true);

    json delConfirm = {{"jsonrpc", "2.0"},
                       {"id", 3},
                       {"method", "tools/call"},
                       {"params",
                        {{"name", "delete_notes"},
                         {"arguments",
                          {{"confirm", true},
                           {"filter", {{"timeMin", 0}, {"timeMax", 1000}}}}}}}};
    auto okBody = rpc(sessionId, delConfirm);
    CHECK(okBody["result"]["isError"] == false);
    CHECK(get_note_pool_manager().get_note_count() == 0);
}

TEST_CASE("mcp bridge take/complete/timeout/duplicate complete") {
    reset_world();

    // complete path
    std::thread worker([] {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        auto jobs = mcp::McpBridge::inst().take_jobs(8);
        REQUIRE(jobs.size() == 1);
        mcp::McpBridge::inst().complete(jobs[0].requestId, true,
                                        json{{"count", 7}}, "");
    });
    json out;
    std::string err;
    const bool ok =
        mcp::McpBridge::inst().submit("get_selection", json::object(), out, err);
    worker.join();
    CHECK(ok);
    CHECK(out["count"] == 7);

    // timeout path
    json out2;
    std::string err2;
    const bool ok2 = mcp::McpBridge::inst().submit(
        "get_selection", json::object(), out2, err2, std::chrono::milliseconds(30));
    CHECK_FALSE(ok2);
    CHECK(err2.find("did not respond") != std::string::npos);

    // duplicate complete after timeout is a no-op
    auto jobs = mcp::McpBridge::inst().take_jobs(8);
    // timeout leaves the job dequeued or not depending on race; complete unknown id is safe
    for (const auto& job : jobs) {
        mcp::McpBridge::inst().complete(job.requestId, true, json::object(), "");
        mcp::McpBridge::inst().complete(job.requestId, true, json::object(), "");
    }
    CHECK(mcp::McpBridge::inst().waiter_count() == 0);
}

TEST_CASE("mcp apply_expression queues a bridge job") {
    reset_world();
    mcp::register_default_tools();

    std::thread worker([] {
        // Drain and fail immediately â€?proves the tool routes through the bridge.
        for (int i = 0; i < 50; ++i) {
            auto jobs = mcp::McpBridge::inst().take_jobs(8);
            for (const auto& job : jobs) {
                mcp::McpBridge::inst().complete(job.requestId, false, json::object(),
                                                "no main thread in unit test");
            }
            if (mcp::McpBridge::inst().pending_count() == 0 &&
                mcp::McpBridge::inst().waiter_count() == 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
                if (mcp::McpBridge::inst().waiter_count() == 0) break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
    });

    auto outcome = mcp::McpToolRegistry::inst().call(
        "apply_expression",
        json{{"expression", "time=time+1"}, {"scope", "all"}});
    worker.join();
    CHECK(outcome.isError);
    CHECK(outcome.payload.contains("error"));
}

TEST_CASE("mcp update_notes and single timing point roundtrip") {
    reset_world();
    auto sessionId = initialize_session();

    json insert = {{"jsonrpc", "2.0"},
                   {"id", 1},
                   {"method", "tools/call"},
                   {"params",
                    {{"name", "insert_notes"},
                     {"arguments",
                      {{"notes",
                        json::array({{{"side", 1},
                                      {"type", 0},
                                      {"time", 800.0},
                                      {"width", 2.0},
                                      {"position", 1.0}}})}}}}}};
    auto insertBody = rpc(sessionId, insert);
    REQUIRE(insertBody["result"]["isError"] == false);
    auto created =
        json::parse(insertBody["result"]["content"][0]["text"].get<std::string>());
    REQUIRE(created["created"].size() == 1);
    const std::string noteId = created["created"][0].get<std::string>();

    json update = {{"jsonrpc", "2.0"},
                   {"id", 2},
                   {"method", "tools/call"},
                   {"params",
                    {{"name", "update_notes"},
                     {"arguments",
                      {{"updates",
                        json::array({{{"noteID", noteId},
                                      {"time", 900.0},
                                      {"position", 3.0}}})}}}}}};
    auto updateBody = rpc(sessionId, update);
    REQUIRE(updateBody["result"]["isError"] == false);
    auto updated =
        json::parse(updateBody["result"]["content"][0]["text"].get<std::string>());
    CHECK(updated["updated"].size() == 1);

    json listNotes = {{"jsonrpc", "2.0"},
                      {"id", 3},
                      {"method", "tools/call"},
                      {"params", {{"name", "list_notes"}, {"arguments", json::object()}}}};
    auto listBody = rpc(sessionId, listNotes);
    auto notes =
        json::parse(listBody["result"]["content"][0]["text"].get<std::string>());
    REQUIRE(notes["notes"].size() >= 1);
    CHECK(notes["notes"][0]["time"] == doctest::Approx(900.0));
    CHECK(notes["notes"][0]["position"] == doctest::Approx(3.0));

    json insTp = {{"jsonrpc", "2.0"},
                  {"id", 4},
                  {"method", "tools/call"},
                  {"params",
                   {{"name", "insert_timing_point"},
                    {"arguments", {{"time", 0.0}, {"bpm", 140.0}, {"meter", 4}}}}}};
    auto insTpBody = rpc(sessionId, insTp);
    CHECK(insTpBody["result"]["isError"] == false);
    CHECK(get_timing_manager().count() == 1);

    json delTp = {{"jsonrpc", "2.0"},
                  {"id", 5},
                  {"method", "tools/call"},
                  {"params",
                   {{"name", "delete_timing_point"},
                    {"arguments", {{"time", 0.0}}}}}};
    auto delTpBody = rpc(sessionId, delTp);
    CHECK(delTpBody["result"]["isError"] == false);
    CHECK(get_timing_manager().count() == 0);
}

TEST_CASE("mcp delete_notes only counts existing ids") {
    reset_world();
    auto sessionId = initialize_session();
    json insert = {{"jsonrpc", "2.0"},
                   {"id", 1},
                   {"method", "tools/call"},
                   {"params",
                    {{"name", "insert_notes"},
                     {"arguments",
                      {{"notes",
                        json::array({{{"side", 0},
                                      {"type", 0},
                                      {"time", 100.0},
                                      {"width", 1.0},
                                      {"position", 1.0}}})}}}}}};
    rpc(sessionId, insert);
    json del = {{"jsonrpc", "2.0"},
                {"id", 2},
                {"method", "tools/call"},
                {"params",
                 {{"name", "delete_notes"},
                  {"arguments",
                   {{"noteIDs", json::array({"missing-id", "also-missing"})}}}}}};
    auto delBody = rpc(sessionId, del);
    REQUIRE(delBody["result"]["isError"] == false);
    auto payload = json::parse(delBody["result"]["content"][0]["text"].get<std::string>());
    CHECK(payload["deleted"] == 0);
    CHECK(get_note_pool_manager().get_note_count() >= 1);
}