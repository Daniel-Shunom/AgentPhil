//// Server State is loaded here
import agent/agent_actor
import dot_env
import env/env
import gleam/erlang/process

pub type GlobalCtx {
  GlobalCtx(
    agent_subj: process.Subject(agent_actor.AgentMessage),
    // Where we send user messages to and the actor relays them to the
    // model provider
    env_vars: env.EnvVars,
  )
}

pub fn init_state() {
  dot_env.load_default()
  let assert Ok(env_vars) = env.load_env()
  let agent_actor = agent_actor.create_agent_actor(env_vars.api_keys)
  GlobalCtx(agent_actor, env_vars)
}
