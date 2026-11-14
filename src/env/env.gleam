import gleam/int
import envoy
import gleam/result

pub type EnvVars {
  EnvVars(
    port: Int,
    bind_ip: String,
    api_keys: Keys
  )
}

pub type Keys {
  Keys(
    open_ai: String,
    anthropic: String
  )
}

pub fn load_env() {
  use bind_ip <- result.try(envoy.get("BIND_IP"))
  use port_str <- result.try(envoy.get("PORT"))
  use port <- result.try(int.parse(port_str))
  use openai_key <- result.try(envoy.get("OPENAI_API_KEY"))
  use anth_key <- result.try(envoy.get("ANTHROPIC_API_KEY"))
  let keys = Keys(
    open_ai: openai_key,
    anthropic: anth_key
  )
  EnvVars(
    port: port,
    bind_ip: bind_ip,
    api_keys: keys
  )
  |> Ok
}
