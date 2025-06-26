defmodule Core.Companies.Invitation do
  @moduledoc """
  Schema for company invitations.

  This schema represents an invitation to join a company. It stores the recipient's
  email, the token used for verification, and the acceptance status. Invitations are
  associated with a company and an inviter (the user who sent the invitation).
  The schema enforces validation rules for invitation data and uniqueness constraints.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "company_invitations" do
    field :email, :string
    field :token, :string
    field :accepted_at, :utc_datetime

    belongs_to :company, Core.Companies.Company
    belongs_to :inviter, Core.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset function for creating or updating an invitation.

  Validates required fields, format constraints, and uniqueness constraints.
  Ensures that only one pending invitation exists per email for each company.

  ## Parameters
    - invitation: The invitation struct to change
    - attrs: Map of attributes to apply to the invitation
  """
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :token, :accepted_at, :company_id, :inviter_id])
    |> validate_required([:email, :token, :company_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> unique_constraint([:company_id, :email], message: "already has a pending invitation")
    |> unique_constraint(:token)
  end
end
