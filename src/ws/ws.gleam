import agent/agent_actor
import gleam/erlang/process
import gleam/io
import gleam/option
import gleam/otp/actor
import gleam/string
import mist
import state/ctx
import ws/ws_msg.{type ModelResponse, ModelResponse}

pub fn ws_handler(req, state: ctx.GlobalCtx) {
  mist.websocket(req, handle, on_init(state, _), on_close)
}

fn handle(
  state: ctx.GlobalCtx,
  message: mist.WebsocketMessage(ModelResponse),
  connection: mist.WebsocketConnection,
) -> mist.Next(ctx.GlobalCtx, ModelResponse) {
  case message {
    mist.Closed | mist.Shutdown -> mist.stop()
    mist.Text(usr_msg) -> {
      actor.send(state.agent_subj, agent_actor.UserMessage(usr_msg))
      mist.continue(state)
    }
    mist.Custom(model_resp) -> {
      let ModelResponse(response) = model_resp
      let _ = mist.send_text_frame(connection, response)
      mist.continue(state)
    }
    _ -> mist.continue(state)
  }
}

fn on_init(state: ctx.GlobalCtx, connection: mist.WebsocketConnection) {
  let ws_subject = process.new_subject()
  // The websocket's subject

  let selector =
    process.new_selector()
    |> process.select(ws_subject)

  let _ = mist.send_text_frame(connection, "Initialized AI provider actor")

  actor.send(state.agent_subj, agent_actor.Init(ws_subject))
  #(state, option.Some(selector))
}

fn on_close(state: ctx.GlobalCtx) {
  { "ShutDown State" <> string.inspect(state) }
  |> io.println()
}
