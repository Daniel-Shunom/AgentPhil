//// Stateful text chat and function tools. glopenai stays behind this module.

import gleam/dynamic.{type Dynamic}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/int
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
    tools -> {
      let request = chat.with_tools(request, list.map(tools, encode_tool))
      // Luna's Chat Completions endpoint requires reasoning off for tools.
      case client.model {
        "gpt-6-luna" ->
          chat.with_reasoning_effort(request, shared.ReasoningNone)
        _ -> request
      }
    }
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

/// Describe failures without exposing raw response bodies or credentials.
pub fn describe_error(failure: ClientError) -> String {
  let detail = case failure {
    TransportError(httpc.ResponseTimeout) -> {
      "the provider timed out. Please try again."
    }

    TransportError(httpc.FailedToConnect(_, _)) -> {
      "could not connect to the provider. Check network and TLS configuration."
    }

    TransportError(httpc.InvalidUtf8Response) -> {
      "the provider returned invalid text."
    }

    ProviderError(error.ApiResponseError(status, api)) -> {
      let reason = case status, api.param {
        400, Some("reasoning_effort") -> {
          "the model rejected the reasoning setting. Function tools on gpt-6-luna require reasoning_effort=none with Chat Completions."
        }

        401, _ -> {
          "authentication failed. Check OPENAI_API_KEY."
        }

        403, _ -> {
          "access denied. Check API project permissions."
        }

        404, _ -> {
          "the configured model is unavailable or this API key lacks access."
        }

        429, _ -> {
          "the provider rate limit or quota was exceeded. Check usage and billing."
        }

        400, _ -> {
          "the provider rejected the request. Check model settings and tool schemas."
        }

        _, _ -> "the provider returned an API error."
      }
      "(HTTP " <> int.to_string(status) <> "): " <> reason
    }
    ProviderError(error.JsonDecodeError(_, _)) -> {
      "could not decode the provider response."
    }

    ProviderError(error.UnexpectedResponse(status, _)) -> {
      "unexpected provider HTTP status " <> int.to_string(status) <> "."
    }

    NoChoices -> {
      "the provider returned no choices."
    }

    ToolsPending -> {
      "tool execution is still pending. Wait for the tool results."
    }

    InvalidToolResults -> {
      "tool results did not match the pending tool calls."
    }
  }
  "Model request failed " <> detail
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
