defmodule Core.SupportStatus do
  @moduledoc """
  Simple module to maintain the current support status (online/offline) using Application environment.
  """

  def get_status do
    Application.get_env(:core, :support_status, "offline")
  end

  def set_status(status) when status in ["online", "offline"] do
    Application.put_env(:core, :support_status, status)
  end
end
