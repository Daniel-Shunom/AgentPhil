import envoy
import gleam/int
import gleam/result
import simplifile

pub type EnvVars {
  EnvVars(port: Int, bind_ip: String, api_keys: Keys)
}

pub type Keys {
  Keys(
    open_ai: String,
    anthropic: String,
    agent_name: String,
    system_prompt: String,
  )
}

pub fn load_env() {
  use bind_ip <- result.try(envoy.get("BIND_IP"))
  use port_str <- result.try(envoy.get("PORT"))
  use port <- result.try(int.parse(port_str))
  use openai_key <- result.try(envoy.get("OPENAI_API_KEY"))
  use anth_key <- result.try(envoy.get("ANTHROPIC_API_KEY"))
  use agent_name <- result.try(envoy.get("AGENT_NAME"))
  use sys_prompt_path <- result.try(envoy.get("SYSTEM_PROMPT_PATH"))
  use sys_prompt <- result.try(
    simplifile.read(sys_prompt_path)
    |> result.replace_error(Nil),
  )

  let keys =
    Keys(
      open_ai: openai_key,
      anthropic: anth_key,
      agent_name: agent_name,
      system_prompt: sys_prompt,
    )
  EnvVars(port: port, bind_ip: bind_ip, api_keys: keys)
  |> Ok
}
