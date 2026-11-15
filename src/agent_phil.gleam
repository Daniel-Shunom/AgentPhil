import state/ctx
import gleam/erlang/process
import mist
import router/router

pub fn main() -> Nil {
  let state = ctx.init_state()
  let assert Ok(_) =
    mist.new(router.router(_, state))
    |> mist.bind(state.env_vars.bind_ip)
    |> mist.port(state.env_vars.port)
    |> mist.start()
  process.sleep_forever()
}
