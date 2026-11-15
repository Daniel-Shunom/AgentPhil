import agent/agent_actor
import env/env
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/response
import gleam/json
import gleam/otp/actor
import providers/chatgpt
import ws/ws_msg

pub fn provider_error_reaches_user_test() {
  let replies = process.new_subject()
  let state =
    agent_actor.init_state(env.Keys(
      "unused",
      "unused",
      "model_error_test",
      "test",
    ))
  let client =
    chatgpt.with_transport(state.oai_client, fn(_) {
      Ok(
        response.new(404)
        |> response.set_body(
          "{\"error\":{\"message\":\"private provider details\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":\"model_not_found\"}}",
        ),
      )
    })
  let subject =
    agent_actor.start_agent_actor(
      agent_actor.AgentState(..state, oai_client: client),
    )
  actor.send(subject, agent_actor.Init(replies))
  actor.send(subject, agent_actor.UserMessage("hello"))
  assert process.receive(replies, 1000)
    == Ok(ws_msg.ModelResponse(
      "Model request failed (HTTP 404): the configured model is unavailable or this API key lacks access.",
    ))
}

pub fn luna_tools_disable_reasoning_test() {
  let state =
    agent_actor.init_state(env.Keys("unused", "unused", "request_test", "test"))
  let client =
    chatgpt.with_transport(state.oai_client, fn(request) {
      // The API rejects Luna function tools unless reasoning is explicitly off.
      assert json.parse(request.body, {
          use effort <- decode.field("reasoning_effort", decode.string)
          decode.success(effort)
        })
        == Ok("none")
      Ok(
        response.new(200)
        |> response.set_body(
          "{\"id\":\"test\",\"object\":\"chat.completion\",\"created\":0,\"model\":\"gpt-6-luna\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"OK\"}}]}",
        ),
      )
    })
  let assert Ok(_) = chatgpt.send_message(client, "hello")
}
