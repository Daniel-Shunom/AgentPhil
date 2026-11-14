import ctx
import gleam/erlang/process
import mist
import router/router

pub fn main() -> Nil {
    let assert Ok(_) =
    mist.new(router.router(_, ctx.init_state()))
    |> mist.bind("0.0.0.0")
    |> mist.port(4000)
    |> mist.start()
  process.sleep_forever()
}
