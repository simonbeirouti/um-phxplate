defmodule Public.PageController do
  use Public, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
