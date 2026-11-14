import agent/agent_actor
import ctx
import gleam/erlang/process
import mist
import router/router

pub fn main() -> Nil {
  let agent_actor = agent_actor.create_agent_actor()
  let state = ctx.GlobalCtx(agent_actor)

  let assert Ok(_) =
    mist.new(router.router(_, state))
    |> mist.bind("0.0.0.0")
    |> mist.port(4000)
    |> mist.start()

  process.sleep_forever()
}
