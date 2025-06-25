defmodule Admin.PageController do
  use Admin, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
