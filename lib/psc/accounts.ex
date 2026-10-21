defmodule Psc.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Psc.Repo

  alias Psc.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

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

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for registering a user with an email and
  password (no hashing — for LiveView form validation).
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Administration

  @doc """
  Lists users for the admin surface, newest first.
  """
  def list_users do
    from(u in User, order_by: [desc: u.inserted_at]) |> Repo.all()
  end

  @doc """
  Gets a user for the admin surface (nil when missing).
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Whether the user may use the admin surface.
  """
  defdelegate admin?(user), to: User

  @doc """
  Promotes a user to admin.
  """
  def promote_admin(%User{} = user), do: update_user_role(user, :admin)

  @doc """
  Demotes a user to member.

  The last admin cannot be demoted: losing every admin would leave the
  instance without anyone able to promote another one.
  """
  def demote_admin(%User{} = user), do: update_user_role(user, :member)

  @doc """
  Sets a user's role.

  Returns `{:error, :last_admin}` when the change would remove the final
  admin, and `{:error, changeset}` for anything the role changeset rejects.
  """
  def update_user_role(%User{} = user, role) when role in [:admin, :member] do
    Repo.transact(fn ->
      if role == :member and user.role == :admin and admin_count() <= 1 do
        Repo.rollback(:last_admin)
      else
        user
        |> User.role_changeset(%{role: role})
        |> Repo.update()
      end
    end)
  end

  @doc """
  The number of admins in the instance.
  """
  def admin_count do
    Repo.one(from(u in User, where: u.role == :admin, select: count(u.id)))
  end

  @doc """
  The addresses configured through `ADMIN_EMAILS`.
  """
  def admin_emails do
    System.get_env("ADMIN_EMAILS", "")
    |> String.split([",", ";", " ", "\n", "\r", "\t"], trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  Bootstraps admins from the environment.

  For every address in `ADMIN_EMAILS` this promotes the existing account, or
  creates it when `ADMIN_PASSWORD` is also set. Creating the account here is
  what makes the bootstrap safe: registration auto-confirms, so promoting an
  address that someone else registered first would hand them the role.

  Returns `{promoted, created, skipped}` counts. It is idempotent and runs on
  every boot, so removing an address from the env does **not** demote it.
  """
  def bootstrap_admins do
    password = System.get_env("ADMIN_PASSWORD")

    Enum.reduce(admin_emails(), {0, 0, []}, fn email, {promoted, created, skipped} ->
      case get_user_by_email(email) do
        %User{role: :admin} ->
          {promoted, created, skipped}

        %User{} = user ->
          _ = promote_admin(user)
          {promoted + 1, created, skipped}

        nil when password in [nil, ""] ->
          {promoted, created, [email | skipped]}

        nil ->
          case register_bootstrap_user(email, password) do
            {:ok, _user} ->
              {promoted, created + 1, skipped}

            {:error, reason} ->
              Logger.warning("admin bootstrap could not create #{email}: #{inspect(reason)}")
              {promoted, created, [email | skipped]}
          end
      end
    end)
    |> then(fn {promoted, created, skipped} -> {promoted, created, Enum.reverse(skipped)} end)
  end

  defp register_bootstrap_user(email, password) do
    %User{}
    |> User.registration_changeset(%{"email" => email, "password" => password})
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        user
        |> confirm_user!()
        |> promote_admin()

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Psc.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Psc.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
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

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Confirms a user account by setting `confirmed_at`.

  Used while email confirmation is disabled for the MVP demo:
  registration is email-less, so accounts are confirmed immediately.
  """
  def confirm_user!(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  @doc """
  Generates and persists a login magic-link token, returning the
  encoded token without emailing it.

  Unlike `deliver_login_instructions/2`, the caller navigates to the
  magic-link URL directly (email delivery is disabled for the MVP).
  """
  def generate_login_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
