defmodule Core.Accounts do
  @moduledoc """
  The Accounts context.

  This context handles all user-related operations including authentication,
  registration, profile management, and admin functions. It provides the core
  functionality for user management throughout the application, including:

  - User authentication and session management
  - User registration and account confirmation
  - Password reset and email change workflows
  - User profile creation and management
  - Role-based access control
  - User onboarding process

  The context integrates with PubSub to broadcast user-related events in real-time
  for LiveView updates across the application.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [get_change: 2]
  alias Core.Repo
  alias Core.PubSub.DataSync

  alias Core.Accounts.{User, UserToken, UserNotifier, Profile}

  @doc """
  Gets a user by email.

  Performs a case-sensitive lookup of a user by their email address.

  ## Parameters
    - email: The email address to search for

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  Verifies that the email exists and the password is correct.
  Returns nil if the email doesn't exist or the password is invalid.

  ## Parameters
    - email: The email address to search for
    - password: The password to verify

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Retrieves a user by their ID, raising an error if not found.

  ## Parameters
    - id: The ID of the user to retrieve

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Lists all users with pagination.

  Retrieves a paginated list of users, excluding the super admin (ID 1).

  ## Parameters
    - opts: Options for pagination
      * `:page` - The page number (starting with 1)
      * `:per_page` - The number of users per page

  ## Examples

      iex> list_users()
      [%User{}, ...]

      iex> list_users(page: 2, per_page: 10)
      [%User{}, ...]
  """
  def list_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)  # Default to 10 users per page
    offset = (page - 1) * per_page

    User
    |> where([u], u.id != 1)  # Exclude the super admin (ID 1)
    |> limit(^per_page)
    |> offset(^offset)
    |> order_by([u], asc: u.id)
    |> Repo.all()
  end

  @doc """
  Counts all users (excluding the super admin).

  Returns the total number of non-super-admin users in the system.

  ## Returns
    - Integer count of users
  """
  def count_users do
    User
    |> where([u], u.id != 1)  # Exclude the super admin (ID 1)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Counts active users (users who have confirmed their email).

  Returns the count of users who have completed email confirmation.

  ## Returns
    - Integer count of confirmed users
  """
  def count_active_users do
    from(u in User, where: not is_nil(u.confirmed_at))
    |> Repo.aggregate(:count, :id)
  end

  ## User registration

  @doc """
  Registers a user.

  Creates a new user account with the provided attributes.
  Validates email, password, and role requirements.

  ## Parameters
    - attrs: Map of attributes for the new user

  ## Examples

      iex> register_user(%{email: "user@example.com", password: "SecurePassword123!"})
      {:ok, %User{}}

      iex> register_user(%{email: "invalid", password: "short"})
      {:error, %Ecto.Changeset{}}
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    changeset =
      user
      |> User.email_changeset(attrs)
      |> User.validate_current_password(password)

    case changeset.valid? do
      true -> {:ok, %{user | email: get_change(changeset, :email)}}
      false -> {:error, %{changeset | action: :update}}
    end
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Ecto.Multi.run(:activity, fn _repo, %{user: updated_user} ->
      {:ok, Core.Tracking.track_user_activity("password_update", updated_user, updated_user)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    changeset = User.confirm_changeset(user)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
    |> Ecto.Multi.run(:activity, fn _repo, %{user: confirmed_user} ->
      {:ok, Core.Tracking.track_user_activity("account_confirmed", confirmed_user, confirmed_user)}
    end)
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Updates a user role (super admin only).

  ## Parameters
    - user_id: The ID of the user to update
    - role: The new role to assign
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, user}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, reason}` on other failures
  """
  def update_user_role(user_id, role, actor) do
    case actor do
      %User{role: :super_admin} ->
        user = get_user!(user_id)
        case Core.Repo.update(Ecto.Changeset.change(user, %{role: role})) do
          {:ok, updated_user} = result ->
            # Track the role update
            Core.Tracking.track_user_activity(
              "role_update",
              updated_user,
              actor,
              %{"role" => updated_user.role}
            )
            # Broadcast user role update
            DataSync.broadcast("users", "all", {:role_updated, %{type: :user, user: updated_user}})
            result
          error -> error
        end
      _ ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Updates a user with the given attributes.

  For role updates, requires super admin privileges.

  ## Examples

      iex> update_user(user, %{role: :admin}, %User{role: :super_admin})
      {:ok, %User{}}

      iex> update_user(user, %{role: :admin}, %User{role: :basic})
      {:error, :unauthorized}
  """
  def update_user(%User{} = user, attrs, actor \\ nil) do
    # Check if this is a role update and if actor has permission
    if (Map.has_key?(attrs, :role) || Map.has_key?(attrs, "role")) &&
       (is_nil(actor) || actor.role != :super_admin) do
      {:error, :unauthorized}
    else
      user
      |> User.role_changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_user} ->
          if Map.has_key?(attrs, :role) || Map.has_key?(attrs, "role") do
            Core.Tracking.track_user_activity(
              "role_update",
              updated_user,
              actor || updated_user,
              %{"role" => updated_user.role}
            )
          end
          {:ok, updated_user}
        error -> error
      end
    end
  end

  @doc """
  Gets a profile by user_id.

  Retrieves a user's profile by their user ID, or returns nil if not found.

  ## Parameters
    - user_id: The ID of the user whose profile to retrieve

  ## Examples

      iex> get_profile_by_user_id(123)
      %Profile{}

      iex> get_profile_by_user_id(456)
      nil
  """
  def get_profile_by_user_id(user_id) do
    Repo.get_by(Profile, user_id: user_id)
  end

  @doc """
  Creates a profile for a user.

  Creates a new profile for a user, tracks the activity, and broadcasts
  the creation event via PubSub.

  ## Parameters
    - user: The user to create a profile for
    - attrs: Map of attributes for the profile

  ## Examples

      iex> create_profile(user, %{first_name: "John", last_name: "Doe"})
      {:ok, %Profile{}}

      iex> create_profile(user, %{first_name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_profile(%User{} = user, attrs) do
    %Profile{user_id: user.id}
    |> Profile.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, profile} = result ->
        # For new profiles, track all provided fields
        changed_fields = Map.take(attrs, ["first_name", "last_name", "bio", "avatar_url", "phone", "location", "website", "social_links"])

        if map_size(changed_fields) > 0 do
          Core.Tracking.track_user_activity("profile_create", user, user, changed_fields)
        end

        # Broadcast profile creation
        DataSync.broadcast("profiles", user.id, {:created, %{type: :profile, profile: profile}})
        # Also broadcast to "all" topic for global updates
        DataSync.broadcast("profiles", "all", {:created, %{type: :profile, profile: profile, global_scope: true}})
        result
      error -> error
    end
  end

  @doc """
  Updates a profile.

  Updates an existing profile with new attributes, tracks changes,
  and broadcasts the update via PubSub.

  ## Parameters
    - profile: The profile to update
    - attrs: Map of attributes to change

  ## Examples

      iex> update_profile(profile, %{first_name: "Jane"})
      {:ok, %Profile{}}

      iex> update_profile(profile, %{first_name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_profile} = result ->
        # Track only changed fields with special handling for avatar_url
        changed_fields = Enum.reduce(["first_name", "last_name", "bio", "avatar_url", "phone", "location", "website", "social_links"], %{}, fn field, acc ->
          old_value = Map.get(profile, String.to_atom(field))

          # Get new value from attrs, handling both string and atom keys
          new_value = cond do
            is_map_key(attrs, field) -> Map.get(attrs, field)
            is_map_key(attrs, String.to_atom(field)) -> Map.get(attrs, String.to_atom(field))
            true -> nil
          end

          # Always include avatar_url when it's present in attrs (for image uploads)
          if field == "avatar_url" && new_value != nil do
            Map.put(acc, field, new_value)
          else
            # For other fields, only include if changed
            if new_value && old_value != new_value do
              Map.put(acc, field, new_value)
            else
              acc
            end
          end
        end)

        if map_size(changed_fields) > 0 do
          user = Repo.get!(User, updated_profile.user_id)
          Core.Tracking.track_user_activity("profile_update", user, user, changed_fields)
        end

        # Broadcast profile update
        DataSync.broadcast("profiles", profile.user_id, {:updated, %{type: :profile, profile: updated_profile}})
        # Also broadcast to "all" topic for global updates
        DataSync.broadcast("profiles", "all", {:updated, %{type: :profile, profile: updated_profile, global_scope: true}})
        result
      error -> error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking profile changes.

  ## Examples

      iex> change_profile(profile)
      %Ecto.Changeset{data: %Profile{}}

  """
  def change_profile(%Profile{} = profile, attrs \\ %{}) do
    Profile.changeset(profile, attrs)
  end

  @doc """
  Marks a user's onboarding as completed.

  Updates a user record to indicate they've completed the onboarding process.

  ## Parameters
    - user: The user who has completed onboarding

  ## Returns
    - `{:ok, user}` on success
    - `{:error, changeset}` on failure
  """
  def complete_onboarding(user) do
    user
    |> Ecto.Changeset.change(onboarding_completed: true)
    |> Repo.update()
  end

  @doc """
  Checks if a user has completed onboarding.

  Returns true if the user has completed the onboarding process.

  ## Parameters
    - user: The user to check

  ## Returns
    - true if onboarding is completed
    - false otherwise
  """
  def onboarding_completed?(%Core.Accounts.User{onboarding_completed: onboarding_completed}), do: onboarding_completed
  def onboarding_completed?(_), do: false

  @doc """
  Delete the user from the application (super admin only).

  Deletes a user and associated records, handling related employee records
  and broadcasting relevant deletion events.

  ## Parameters
    - user: The user to delete
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, user}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, changeset}` on failure
  """
  def delete_user(%User{} = user, actor) do
    case actor do
      %User{role: :super_admin} ->
        # First find and delete any associated employee records
        if user.profile do
          case Core.Companies.get_employee_by_user_id(user.id) do
            nil -> :ok
            employee ->
              # Delete the employee first
              Core.Companies.delete_employee(employee)
          end
        end

        # Preload companies to ensure proper cascade deletion
        user = Repo.preload(user, [:companies, :profile])

        # Store company IDs before deletion for broadcasting
        company_ids = Enum.map(user.companies, & &1.id)

        # Then delete the user with proper changeset to handle company deletion
        case user |> User.delete_changeset() |> Repo.delete() do
          {:ok, deleted_user} = result ->
            # Track the user deletion
            Core.Tracking.track_user_activity(
              "user_delete",
              deleted_user,
              actor,
              %{"deleted_user_id" => deleted_user.id, "deleted_user_email" => deleted_user.email}
            )

            # Broadcast user deletion
            DataSync.broadcast("users", "all", {:deleted, %{type: :user, id: deleted_user.id}})

            # Broadcast profile deletion if exists
            if deleted_user.profile do
              DataSync.broadcast("profiles", deleted_user.profile.id, {:deleted, %{type: :profile, id: deleted_user.profile.id}})
            end

            # Broadcast company deletions
            Enum.each(company_ids, fn company_id ->
              DataSync.broadcast("companies", "all", {:deleted, %{type: :company, id: company_id}})
              DataSync.broadcast("companies", company_id, {:deleted, %{type: :company, id: company_id}})
            end)

            # Force logout for the deleted user
            DataSync.broadcast("users", deleted_user.id, {:force_logout, %{type: :user, id: deleted_user.id}})

            result

          error ->
            error
        end
      _ ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Updates a user's profile.

  ## Examples

      iex> update_user_profile(user, %{field: new_value})
      {:ok, %Profile{}}

      iex> update_user_profile(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_profile(%User{} = user, attrs) do
    profile = user.profile || %Profile{user_id: user.id}

    profile
    |> Profile.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, updated_profile} = result ->
        # For new profiles, track all fields
        # For existing profiles, track only changed fields
        changed_fields = if profile.id do
          # Update - track only changed fields
          Enum.reduce(["first_name", "last_name", "bio", "avatar_url", "phone", "location", "website", "social_links"], %{}, fn field, acc ->
            old_value = Map.get(profile, String.to_atom(field))

            # Get new value from attrs, handling both string and atom keys
            new_value = cond do
              is_map_key(attrs, field) -> Map.get(attrs, field)
              is_map_key(attrs, String.to_atom(field)) -> Map.get(attrs, String.to_atom(field))
              true -> nil
            end

            # Always include avatar_url when it's present in attrs (for image uploads)
            if field == "avatar_url" && new_value != nil do
              Map.put(acc, field, new_value)
            else
              # For other fields, only include if changed
              if new_value && old_value != new_value do
                Map.put(acc, field, new_value)
              else
                acc
              end
            end
          end)
        else
          # New profile - track all provided fields
          Map.take(attrs, ["first_name", "last_name", "bio", "avatar_url", "phone", "location", "website", "social_links"])
        end

        if map_size(changed_fields) > 0 do
          action = if profile.id, do: "profile_update", else: "profile_create"
          Core.Tracking.track_user_activity(action, user, user, changed_fields)
        end

        # Broadcast profile update or creation
        event_type = if profile.id, do: :updated, else: :created
        DataSync.broadcast("profiles", user.id, {event_type, %{type: :profile, profile: updated_profile}})
        # Also broadcast to "all" topic for global updates
        DataSync.broadcast("profiles", "all", {event_type, %{type: :profile, profile: updated_profile, global_scope: true}})
        result
      error -> error
    end
  end

  @doc """
  Updates a user's sidebar state.

  Updates the sidebar state for a user between "expanded" and "collapsed".

  ## Parameters
    - user: The user to update
    - state: The new sidebar state ("expanded" or "collapsed")

  ## Examples

      iex> update_user_sidebar_state(user, "collapsed")
      {:ok, %User{}}

      iex> update_user_sidebar_state(user, "invalid")
      {:error, %Ecto.Changeset{}}
  """
  def update_user_sidebar_state(%User{} = user, state) do
    user
    |> User.sidebar_state_changeset(%{sidebar_state: state})
    |> Repo.update()
  end

  @doc """
  Gets a user's sidebar state.

  Returns the current sidebar state for a user, defaulting to "expanded"
  if not set.

  ## Parameters
    - user: The user to get the sidebar state for

  ## Examples

      iex> get_user_sidebar_state(user)
      "expanded"
  """
  def get_user_sidebar_state(%User{sidebar_state: state}) when state in ["expanded", "collapsed"] do
    state
  end
  def get_user_sidebar_state(_user), do: "expanded"

  @doc """
  Deletes a user.

  Deletes the specified user from the database. This will fail if the user
  has foreign key constraints (like owning companies).

  ## Parameters
    - user: The user to delete

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user_with_companies)
      {:error, %Ecto.Changeset{}}
  """
  def delete_user(%User{} = user) do
    user
    |> User.delete_changeset()
    |> Repo.delete()
  end
end
