import child_process
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/option
import gleam/otp/actor
import gleam/result
import providers/chatgpt

pub type ToolMsg(a) {
  Tool(call: chatgpt.ToolCall)
  InitTool(reply_to: process.Subject(a))
}

pub type ToolBox(a) {
  ToolBox(
    reciever: option.Option(process.Subject(a)),
    transport: fn(process.Subject(a), chatgpt.ToolResult) -> Nil,
  )
}

pub fn definitions() -> List(chatgpt.Tool) {
  let assert Ok(parameters) =
    json.parse(
      "{
    \"type\":\"object\",
    \"properties\":{
      \"exe\":{\"type\":\"string\"},
      \"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},
      \"cwd\":{\"type\":\"string\"}
    },
    \"required\":[\"exe\",\"args\",\"cwd\"]
  }",
      decode.dynamic,
    )
  [
    chatgpt.Tool(
      "exec",
      "You have access to a computer. Run an executable with arguments in a working directory. Use this to inspect the system and discover available commands and files. To use shell syntax, run the appropriate shell explicitly. Results contain status_code and output, or error.",
      parameters,
    ),
  ]
}

pub fn init_toolbox(state) {
  let assert Ok(data) =
    actor.new(state)
    |> actor.on_message(on_message)
    |> actor.start()
  data.data
}

fn on_message(state: ToolBox(a), msg: ToolMsg(a)) {
  case msg {
    Tool(call) -> {
      process.spawn_unlinked(fn() {
        let output = execute(call)
        case state.reciever {
          option.None -> Nil
          option.Some(subj) -> {
            state.transport(subj, chatgpt.ToolResult(call.id, output))
          }
        }
      })
      actor.continue(state)
    }

    InitTool(subj) -> {
      let new_state = ToolBox(..state, reciever: option.Some(subj))
      actor.continue(new_state)
    }
  }
}

fn execute(call: chatgpt.ToolCall) -> String {
  let result = case call.name {
    "exec" -> {
      json.parse(call.arguments, {
        use exe <- decode.field("exe", decode.string)
        use args <- decode.field("args", decode.list(decode.string))
        use cwd <- decode.field("cwd", decode.string)
        decode.success(#(exe, args, cwd))
      })
      |> result.map_error(fn(_) {
        "Invalid exec arguments: expected exe, args, cwd"
      })
      |> result.try(fn(args) {
        let #(exe, args, cwd) = args
        child_process.exec(exe, args, cwd)
        |> result.map_error(child_process.describe_start_error)
      })
    }
    _ -> Error("Unknown tool: " <> call.name)
  }
  case result {
    Ok(out) ->
      json.object([
        #("status_code", json.int(out.status_code)),
        #("output", json.string(out.output)),
      ])
    Error(error) -> json.object([#("error", json.string(error))])
  }
  |> json.to_string
}
