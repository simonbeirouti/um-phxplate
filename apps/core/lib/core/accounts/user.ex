defmodule Core.Accounts.User do
  @moduledoc """
  Schema for user accounts.

  This schema represents a user in the system, storing authentication details,
  role information, and account status. Users can have roles (basic, admin, or super admin)
  that determine their permissions in the system. The schema includes validation logic
  for email and password requirements, and establishes associations with profiles,
  subscriptions, tokens, and companies.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime
    field :role, Ecto.Enum, values: [:basic, :admin, :super_admin], default: :basic
    field :onboarding_completed, :boolean, default: false
    field :sidebar_state, :string, default: "expanded"

    has_one :profile, Core.Accounts.Profile
    has_one :subscription, Core.Subscriptions.Subscription
    has_many :tokens, Core.Accounts.UserToken
    has_many :companies, Core.Companies.Company, foreign_key: :owner_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registration.

  Creates a changeset for new user registration with comprehensive validation
  for email and password fields. Enforces security requirements for passwords
  and ensures email uniqueness.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email, in case
      you don't want to validate the uniqueness of the email (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :role, :onboarding_completed])
    |> validate_email(opts)
    |> validate_password(opts)
    |> validate_role()
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp validate_role(changeset) do
    changeset
    |> validate_required([:role])
    |> validate_inclusion(:role, [:basic, :admin, :super_admin])
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Core.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  Validates email format and uniqueness, and requires the email to
  be different from the current one.

  ## Parameters
    - user: The user struct to change
    - attrs: Map of attributes to apply to the user
    - opts: Options controlling validation behavior
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  Validates password requirements and confirmation matching.

  ## Parameters
    - user: The user struct to change
    - attrs: Map of attributes to apply to the user
    - opts: Options controlling validation behavior

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.

  Sets the confirmed_at field to the current UTC timestamp,
  marking the account as verified.

  ## Parameters
    - user: The user struct to confirm
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  Safely compares the provided password against the stored hash.
  Uses Bcrypt's timing-attack resistant comparison.

  ## Parameters
    - user: The user struct with a hashed password
    - password: The plain text password to verify

  ## Returns
    - true if the password matches
    - false otherwise
  """
  def valid_password?(%Core.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.

  Checks if the provided password matches the user's current password.
  Used when changing sensitive information to verify user identity.

  ## Parameters
    - changeset: The changeset to validate
    - password: The plain text password to verify
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  Returns true if the user has admin privileges.

  Checks if the user's role is either admin or super_admin.

  ## Parameters
    - user: The user struct to check
  """
  def is_admin?(%__MODULE__{role: role}), do: role in [:admin, :super_admin]

  @doc """
  Returns true if the user has super admin privileges.

  Checks if the user's role is specifically super_admin.

  ## Parameters
    - user: The user struct to check
  """
  def is_super_admin?(%__MODULE__{role: :super_admin}), do: true
  def is_super_admin?(_), do: false

  @doc """
  Returns true if the user has basic privileges.

  Checks if the user's role is specifically basic.

  ## Parameters
    - user: The user struct to check
  """
  def is_basic?(%__MODULE__{role: :basic}), do: true
  def is_basic?(_), do: false

  @doc """
  A user changeset for updating the role.

  Creates a changeset that only allows changing the user's role,
  with validation to ensure the role is valid.

  ## Parameters
    - user: The user struct to change
    - attrs: Map of attributes containing the new role
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_role()
  end

  @doc """
  A user changeset for updating the sidebar state.

  Creates a changeset that only allows changing the user's sidebar state
  between "expanded" and "collapsed".

  ## Parameters
    - user: The user struct to change
    - attrs: Map of attributes containing the new sidebar_state
  """
  def sidebar_state_changeset(user, attrs) do
    user
    |> cast(attrs, [:sidebar_state])
    |> validate_required([:sidebar_state])
    |> validate_inclusion(:sidebar_state, ["expanded", "collapsed"])
  end

  @doc """
  A user changeset for deleting the user.

  Creates a changeset that enforces foreign key constraints,
  ensuring the user can't be deleted if they own companies.

  ## Parameters
    - user: The user struct to delete
  """
  def delete_changeset(user) do
    change(user)
    |> foreign_key_constraint(:companies, name: "companies_owner_id_fkey")
  end

end
