defmodule Core.Accounts.Profile do
  @moduledoc """
  Schema for user profiles.

  This schema represents a user's profile information in the system, including
  personal details like name, contact information, bio, and profile image.
  The profile is associated with a user and provides additional information
  beyond the basic authentication data. If no avatar is provided, a default
  one is generated.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :first_name, :last_name, :bio, :avatar_url, :phone, :location, :website, :social_links, :user_id, :inserted_at, :updated_at]}

  schema "profiles" do
    field :first_name, :string
    field :last_name, :string
    field :bio, :string
    field :avatar_url, :string
    field :phone, :string
    field :location, :string
    field :website, :string
    field :social_links, :map, default: %{}

    belongs_to :user, Core.Accounts.User

    timestamps()
  end

  @doc """
  Changeset function for creating or updating a profile.

  Validates required fields, foreign key constraints, and sets a default avatar
  if one isn't provided.

  ## Parameters
    - profile: The profile struct to change
    - attrs: Map of attributes to apply to the profile
  """
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:first_name, :last_name, :bio, :avatar_url, :phone, :location, :website, :social_links, :user_id])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
    |> put_default_avatar()
  end

  defp put_default_avatar(changeset) do
    if get_field(changeset, :avatar_url) == nil do
      put_change(changeset, :avatar_url, default_avatar())
    else
      changeset
    end
  end

  @doc """
  Generates a random avatar URL using DiceBear's Avataaars API.

  Creates a random seed and constructs a URL that will render a consistent
  avatar for that seed value.
  """
  def default_avatar do
    seed = :crypto.strong_rand_bytes(10) |> Base.encode16(case: :lower)
    "https://api.dicebear.com/7.x/avataaars/svg?seed=#{seed}"
  end
end
