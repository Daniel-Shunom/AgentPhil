import gleam/bytes_tree
import gleam/http/request
import gleam/http/response
import gleam/list
import mist
import ws/ws

pub fn router(req: request.Request(mist.Connection), ctx) {
  case list.first(request.path_segments(req)) {
    Ok("ws") -> ws.ws_handler(req, ctx)
    _ -> {
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
    }
  }
}
