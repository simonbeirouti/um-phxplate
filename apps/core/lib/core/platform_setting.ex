defmodule Core.PlatformSetting do
  @moduledoc """
  Schema for managing platform-wide settings.

  This schema stores configuration values that control which features
  are enabled across the platform, such as subscription plans and
  single purchase products.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "platform_settings" do
    field :key, :string
    field :value, :boolean
    field :description, :string

    timestamps()
  end

  @doc false
  def changeset(platform_setting, attrs) do
    platform_setting
    |> cast(attrs, [:key, :value, :description])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
