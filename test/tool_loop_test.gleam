import agent/agent_actor
import env/env
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/string
import providers/chatgpt
import ws/ws_msg

pub fn tool_loop_test() {
  let requests = process.new_subject()
  let replies = process.new_subject()
  let transport = fn(request: request.Request(String)) {
    process.send(requests, request.body)
    let message = case list.length(tool_results(request.body)) {
      0 ->
        json.object([
          #("role", json.string("assistant")),
          #(
            "tool_calls",
            json.array(
              [
                command("success", "io:format(\"hello\"), halt()."),
                call(
                  "missing",
                  "exec",
                  "{\"exe\":\"agent_phil_missing_executable\",\"args\":[],\"cwd\":\".\"}",
                ),
                call("invalid", "exec", "{}"),
                call("unknown", "unknown", "{}"),
              ],
              fn(x) { x },
            ),
          ),
        ])
      4 ->
        json.object([
          #("role", json.string("assistant")),
          #(
            "tool_calls",
            json.array([command("nonzero", "halt(7).")], fn(x) { x }),
          ),
        ])
      _ ->
        json.object([
          #("role", json.string("assistant")),
          #("content", json.string("done")),
        ])
    }
    Ok(response.new(200) |> response.set_body(completion(message)))
  }
  let keys = env.Keys("unused", "unused", "tool_loop_test", "test")
  let state = agent_actor.init_state(keys)
  let client = chatgpt.with_transport(state.oai_client, transport)
  let subject =
    agent_actor.start_agent_actor(
      agent_actor.AgentState(..state, oai_client: client),
    )
  actor.send(subject, agent_actor.Init(replies))
  actor.send(subject, agent_actor.UserMessage("run tools"))
  let assert Ok(first) = process.receive(requests, 1000)
  assert string.contains(first, "exec")
  let assert Ok(second) = process.receive(requests, 10_000)
  let results = tool_results(second)
  assert list.length(results) == 4
  assert list.any(results, fn(r) {
    r.id == "success" && string.contains(r.output, "hello")
  })
  assert list.all(["missing", "invalid", "unknown"], fn(id) {
    list.any(results, fn(r) { r.id == id && string.contains(r.output, "error") })
  })
  let assert Ok(third) = process.receive(requests, 10_000)
  let results = tool_results(third)
  assert list.length(results) == 5
  let assert Ok(nonzero) = list.find(results, fn(r) { r.id == "nonzero" })
  assert json.parse(nonzero.output, {
      use code <- decode.field("status_code", decode.int)
      decode.success(code)
    })
    == Ok(7)
  assert process.receive(replies, 1000) == Ok(ws_msg.ModelResponse("done"))
  actor.send(subject, agent_actor.UserMessage("still there?"))
  assert process.receive(replies, 1000) == Ok(ws_msg.ModelResponse("done"))
}

fn command(id: String, expression: String) {
  call(
    id,
    "exec",
    json.object([
      #("exe", json.string("erl")),
      #(
        "args",
        json.array(["+S", "1", "-noshell", "-eval", expression], json.string),
      ),
      #("cwd", json.string(".")),
    ])
      |> json.to_string,
  )
}

fn tool_results(body: String) {
  let assert Ok(messages) =
    json.parse(body, {
      use messages <- decode.field("messages", decode.list(decode.dynamic))
      decode.success(messages)
    })
  list.filter_map(messages, fn(message) {
    decode.run(message, {
      use id <- decode.field("tool_call_id", decode.string)
      use output <- decode.field("content", decode.string)
      decode.success(chatgpt.ToolResult(id, output))
    })
  })
}

fn call(id: String, name: String, arguments: String) {
  json.object([
    #("id", json.string(id)),
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", json.string(name)),
        #("arguments", json.string(arguments)),
      ]),
    ),
  ])
}

fn completion(message: json.Json) {
  json.object([
    #("id", json.string("test")),
    #("object", json.string("chat.completion")),
    #("created", json.int(0)),
    #("model", json.string("test")),
    #(
      "choices",
      json.array(
        [
          json.object([
            #("index", json.int(0)),
            #("message", message),
          ]),
        ],
        fn(x) { x },
      ),
    ),
  ])
  |> json.to_string
}
