//// I think the loop is really just an actor that can either 
//// recieve user message, an agent message, or a tool call message.
//// Probably something like that.

import env/env
import agent/agent_job
import gleam/erlang/process
import gleam/list
import gleam/option
import gleam/otp/actor
import ws/ws_msg

pub fn create_agent_actor(keys: env.Keys) {
  let assert Ok(started) =
    actor.new(init_state(keys))
    |> actor.on_message(msg_handler)
    |> actor.named(process.new_name("BASE_AGENT"))
    // Ideally, we would want this to be discoverabe from a file or something
    |> actor.start()
  started.data
}

pub type AgentMessage {
  Init(process.Subject(ws_msg.ModelResponse))
  UserMessage(message: String)
  ModelMessage(message: String)
  ToolCall(args: List(String))
}

pub type AgentState {
  AgentState(
    msg_history: List(AgentMessage),
    job_registry: agent_job.AgentJobRegistry,
    ws_subject: option.Option(process.Subject(ws_msg.ModelResponse)),
    api_keys: env.Keys
  )
}

pub fn init_state(keys) -> AgentState {
  AgentState(
    msg_history: list.new(),
    job_registry: agent_job.create_job_registry(),
    ws_subject: option.None,
    api_keys: keys
  )
}

fn msg_handler(
  state: AgentState,
  msg: AgentMessage,
) -> actor.Next(AgentState, AgentMessage) {
  case msg {
    Init(ws_subject) -> {
      let new_state = AgentState(..state, ws_subject: option.Some(ws_subject))
      actor.continue(new_state)
    }

    UserMessage(user_msg) -> {
      // If a user message gets here, send it to OpenAI
      case state.ws_subject {
        option.None -> actor.continue(state)
        option.Some(subj) -> {
          let msg = "[RecV] Model actor recieved the following user message and will be forward it to the the AI provdier: \"" <> user_msg <> "\""
          actor.send(subj, ws_msg.ModelResponse(msg))
          actor.continue(state)
        }
      }
      actor.continue(state)
    }

    ModelMessage(model_msg) -> {
      // send back to the user?
      actor.continue(state)
    }

    ToolCall(tool_call) -> {
      // so I'm thinking that, The actor sends this to it's self. After we get a model message and 
      // we need to make a tool call.
      actor.continue(state)
    }
  }
}
