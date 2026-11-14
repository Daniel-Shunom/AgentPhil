//// Server State is loaded here
import dot_env
import env/env
import agent/agent_actor
import gleam/erlang/process

pub type GlobalCtx {
  GlobalCtx(
    agent_subj: process.Subject(agent_actor.AgentMessage),
    // Where we send user messages to and the actor relays them to the
    // model provider
    env_vars: env.EnvVars
  )
}

pub fn init_state() {
  dot_env.load_default()
  let agent_actor = agent_actor.create_agent_actor()
  let assert Ok(env_vars) = env.load_env()
  GlobalCtx(agent_actor, env_vars)
}
