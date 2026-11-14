import agent/agent_actor
import gleam/erlang/process

pub type GlobalCtx {
  GlobalCtx(
    agent_subj: process.Subject(agent_actor.AgentMessage),
    // Where we send user messages to and the actor relays them to the
    // model provider
  )
}
