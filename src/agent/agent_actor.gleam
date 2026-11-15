//// The actor coordinates messages; the provider client owns the conversation.

import agent/agent_job
import env/env
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import providers/chatgpt
import ws/ws_msg

pub fn create_agent_actor(keys: env.Keys) {
  let assert Ok(started) =
    actor.new(init_state(keys))
    |> actor.on_message(msg_handler)
    |> actor.named(process.new_name(keys.agent_name))
    |> actor.start()
  started.data
}

pub type AgentMessage {
  Init(process.Subject(ws_msg.ModelResponse))
  UserMessage(message: String)
  ToolResults(results: List(chatgpt.ToolResult))
}

pub type AgentState {
  AgentState(
    oai_client: chatgpt.OpenAIClient,
    pending_tool_calls: List(chatgpt.ToolCall),
    context: List(String),
    job_registry: agent_job.AgentJobRegistry,
    ws_subject: option.Option(process.Subject(ws_msg.ModelResponse)),
    api_keys: env.Keys,
  )
}

pub fn init_state(keys: env.Keys) -> AgentState {
  AgentState(
    oai_client: chatgpt.new(
      keys.open_ai,
      keys.system_prompt,
      "gpt-6-luna",
      [],
    ),
    pending_tool_calls: [],
    context: list.new(),
    job_registry: agent_job.create_job_registry(),
    ws_subject: option.None,
    api_keys: keys,
  )
}

fn msg_handler(
  state: AgentState,
  msg: AgentMessage,
) -> actor.Next(AgentState, AgentMessage) {
  case msg {
    Init(ws_subject) ->
      actor.continue(AgentState(..state, ws_subject: option.Some(ws_subject)))
    UserMessage(message) ->
      handle_reply(state, chatgpt.send_message(state.oai_client, message))
    ToolResults(results) ->
      handle_reply(
        state,
        chatgpt.submit_tool_results(state.oai_client, results),
      )
  }
}

fn handle_reply(
  state: AgentState,
  response: Result(#(chatgpt.OpenAIClient, chatgpt.Reply), chatgpt.ClientError),
) -> actor.Next(AgentState, AgentMessage) {
  case response {
    Error(_) -> {
      notify(state, "Model request failed; please try again.")
      actor.continue(state)
    }
    Ok(#(client, reply)) -> {
      case reply.text {
        option.Some(text) -> notify(state, text)
        option.None -> Nil
      }
      case reply.refusal {
        option.Some(text) -> notify(state, text)
        option.None -> Nil
      }
      actor.continue(
        AgentState(
          ..state,
          oai_client: client,
          pending_tool_calls: reply.tool_calls,
        ),
      )
    }
  }
}

fn notify(state: AgentState, text: String) -> Nil {
  case state.ws_subject {
    option.Some(subject) -> process.send(subject, ws_msg.ModelResponse(text))
    option.None -> Nil
  }
}
