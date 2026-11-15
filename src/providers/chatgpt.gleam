//// Stateful text chat and function tools. glopenai stays behind this module.

import gleam/dynamic.{type Dynamic}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import glopenai/chat
import glopenai/config
import glopenai/error
import glopenai/shared

pub opaque type OpenAIClient {
  OpenAIClient(
    config: config.Config,
    model: String,
    tools: List(Tool),
    history: List(chat.ChatMessage),
    pending: List(ToolCall),
    transport: Transport,
  )
}

pub type Tool {
  Tool(name: String, description: String, parameters: Dynamic)
}

pub type ToolCall {
  ToolCall(id: String, name: String, arguments: String)
}

pub type ToolResult {
  ToolResult(id: String, output: String)
}

pub type Reply {
  Reply(
    text: Option(String),
    refusal: Option(String),
    tool_calls: List(ToolCall),
  )
}

pub type ClientError {
  TransportError(httpc.HttpError)
  ProviderError(error.GlopenaiError)
  NoChoices
  ToolsPending
  InvalidToolResults
}

pub type Transport =
  fn(Request(String)) -> Result(Response(String), httpc.HttpError)

pub fn new(
  key: String,
  prompt: String,
  model: String,
  tools: List(Tool),
) -> OpenAIClient {
  OpenAIClient(
    config: config.new(key),
    model: model,
    tools: tools,
    history: [chat.system_message(prompt)],
    pending: [],
    transport: httpc.send,
  )
}

pub fn with_transport(
  client: OpenAIClient,
  transport: Transport,
) -> OpenAIClient {
  OpenAIClient(..client, transport: transport)
}

pub fn send_message(
  client: OpenAIClient,
  text: String,
) -> Result(#(OpenAIClient, Reply), ClientError) {
  case client.pending {
    [] -> complete(client, [chat.user_message(text)])
    _ -> Error(ToolsPending)
  }
}

pub fn submit_tool_results(
  client: OpenAIClient,
  results: List(ToolResult),
) -> Result(#(OpenAIClient, Reply), ClientError) {
  let ids = list.map(results, fn(result) { result.id })
  let valid = case client.pending {
    [] -> False
    calls ->
      list.length(ids) == list.length(calls)
      && list.length(list.unique(ids)) == list.length(ids)
      && list.all(calls, fn(call) { list.contains(ids, call.id) })
  }
  case valid {
    False -> Error(InvalidToolResults)
    True ->
      complete(
        client,
        list.map(results, fn(result) {
          chat.tool_message(result.output, result.id)
        }),
      )
  }
}

fn complete(
  client: OpenAIClient,
  messages: List(chat.ChatMessage),
) -> Result(#(OpenAIClient, Reply), ClientError) {
  let history = list.append(client.history, messages)
  let request = chat.new_create_request(client.model, history)
  let request = case client.tools {
    [] -> request
    tools -> chat.with_tools(request, list.map(tools, encode_tool))
  }
  use response <- result.try(
    client.transport(chat.create_request(client.config, request))
    |> result.map_error(TransportError),
  )
  use completion <- result.try(
    chat.create_response(response) |> result.map_error(ProviderError),
  )
  use choice <- result.try(
    list.first(completion.choices) |> result.replace_error(NoChoices),
  )
  let message = choice.message
  let calls = message.tool_calls |> option.unwrap([]) |> list.map(decode_call)
  let assistant =
    chat.AssistantMessage(
      content: option.map(message.content, chat.AssistantTextContent),
      refusal: message.refusal,
      name: None,
      tool_calls: message.tool_calls,
    )
  Ok(#(
    OpenAIClient(
      ..client,
      history: list.append(history, [assistant]),
      pending: calls,
    ),
    Reply(message.content, message.refusal, calls),
  ))
}

fn encode_tool(tool: Tool) -> chat.ChatCompletionTool {
  chat.FunctionTool(shared.FunctionObject(
    name: tool.name,
    description: Some(tool.description),
    parameters: Some(tool.parameters),
    strict: None,
  ))
}

fn decode_call(call: chat.ToolCall) -> ToolCall {
  let chat.FunctionToolCall(id, function) = call
  ToolCall(id, function.name, function.arguments)
}
