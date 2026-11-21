//// The actor coordinates messages; the provider client owns the conversation.

import agent/agent_job
import env/env
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import providers/chatgpt
import tools/tools
import ws/ws_msg

pub fn create_agent_actor(keys: env.Keys) {
  start_agent_actor(init_state(keys))
}

pub fn start_agent_actor(state: AgentState) {
  let assert Ok(started) =
    actor.new(state)
    |> actor.on_message(msg_handler)
    |> actor.named(process.new_name(state.api_keys.agent_name))
    |> actor.start()

  let toolbox =
    tools.ToolBox(
      reciever: option.Some(started.data),
      transport: fn(subj, result) { actor.send(subj, ToolResults([result])) },
    )

  actor.send(started.data, InitToolBox(tools.init_toolbox(toolbox)))
  started.data
}

pub type AgentMessage {
  InitToolBox(process.Subject(tools.ToolMsg(AgentMessage)))
  Init(process.Subject(ws_msg.ModelResponse))
  UserMessage(message: String)
  ToolResults(results: List(chatgpt.ToolResult))
}

pub type AgentState {
  AgentState(
    oai_client: chatgpt.OpenAIClient,
    pending_tool_calls: List(chatgpt.ToolCall),
    tool_results: dict.Dict(String, chatgpt.ToolResult),
    context: List(String),
    incoming_user_msgs: List(String),
    job_registry: agent_job.AgentJobRegistry,
    tool_box_subject: option.Option(
      process.Subject(tools.ToolMsg(AgentMessage)),
    ),
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
      tools.definitions(),
    ),
    pending_tool_calls: list.new(),
    tool_results: dict.new(),
    context: list.new(),
    incoming_user_msgs: list.new(),
    job_registry: agent_job.create_job_registry(),
    tool_box_subject: option.None,
    ws_subject: option.None,
    api_keys: keys,
  )
}

fn msg_handler(
  state: AgentState,
  msg: AgentMessage,
) -> actor.Next(AgentState, AgentMessage) {
  case msg {
    InitToolBox(toolbox) -> {
      let new_state =
        AgentState(..state, tool_box_subject: option.Some(toolbox))
      actor.continue(new_state)
    }

    Init(ws_subject) -> {
      actor.continue(AgentState(..state, ws_subject: option.Some(ws_subject)))
    }

    UserMessage(message) -> {
      let new_state = AgentState(
        ..state,
        // Inefficient for now but idc.
        incoming_user_msgs: list.append(state.incoming_user_msgs, [message])
      )
      // Probably move the message sending into another actor, a coordinator actor perhaps?
      chatgpt.send_message(state.oai_client, message)
      |> handle_reply(new_state, _)
    }

    ToolResults(results) -> {
      let results =
        list.fold(results, state.tool_results, fn(acc, result) {
          dict.insert(acc, result.id, result)
        })
      let state = AgentState(..state, tool_results: results)
      case dict.size(results) == list.length(state.pending_tool_calls) {
        True ->
          handle_reply(
            state,
            chatgpt.submit_tool_results(state.oai_client, dict.values(results)),
          )
        False -> actor.continue(state)
      }
    }
  }
}

fn handle_reply(
  state: AgentState,
  response: Result(#(chatgpt.OpenAIClient, chatgpt.Reply), chatgpt.ClientError),
) -> actor.Next(AgentState, AgentMessage) {
  case response {
    Error(error) -> {
      case error {
        chatgpt.ToolsPending -> {}
        _ -> {
          notify(state, chatgpt.describe_error(error))
          actor.continue(state)
        }
      }
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

      case state.tool_box_subject {
        option.Some(subject) ->
          list.each(reply.tool_calls, fn(call) {
            actor.send(subject, tools.Tool(call))
          })
        option.None -> Nil
      }

      actor.continue(
        AgentState(
          ..state,
          oai_client: client,
          pending_tool_calls: reply.tool_calls,
          tool_results: dict.new(),
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
