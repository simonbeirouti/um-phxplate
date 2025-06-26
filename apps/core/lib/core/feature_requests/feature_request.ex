defmodule Core.FeatureRequests.FeatureRequest do
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User

  schema "feature_requests" do
    field :priority_rating, :integer
    field :feasibility_rating, :integer  # Keeping for backward compatibility but using as request_type
    field :feature_description, :string
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(feature_request, attrs) do
    feature_request
    |> cast(attrs, [:priority_rating, :feasibility_rating, :feature_description, :user_id])
    |> validate_required([:priority_rating, :feasibility_rating, :feature_description])
    |> validate_number(:priority_rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:feasibility_rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 2)  # Now 1=Feature Request, 2=Feedback
    |> validate_length(:feature_description, min: 20)
  end
end
