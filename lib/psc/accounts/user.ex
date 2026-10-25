defmodule Psc.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # Authorization. Never cast from user input: roles are changed through
    # `Psc.Accounts.update_user_role/2` or the release bootstrap.
    field :role, Ecto.Enum, values: [:member, :admin], default: :member
    field :agent_api_key, :string, redact: true
    field :agent_model, :string
    field :default_agent_connection_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  A user changeset for registration with an email and password.

  No email confirmation: the account is confirmed by the caller immediately
  after insert (email-based confirmation is a much-later feature).
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_length(:email, max: 160)

    # A blank field already reports "can't be blank"; adding a format error for
    # the empty string would just stack noise under the same input.
    changeset =
      case get_change(changeset, :email) do
        blank when blank in [nil, ""] ->
          changeset

        _email ->
          validate_format(changeset, :email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
            message: "must have the @ sign and no spaces"
          )
      end

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Psc.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

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

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, message: "should be at least 12 characters")
    |> validate_length(:password, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
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

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  A changeset for changing a user's role.

  Deliberately separate from the registration and email changesets: a role is
  never accepted from a request payload that merely passes through `cast/3`
  from a form.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, [:member, :admin])
  end

  @doc """
  Stores the user's provider API key and model.

  Kept out of the registration and profile changesets on purpose: programmatic
  fields, never cast from a generic form. A blank key removes it.
  """
  def agent_key_changeset(user, attrs) do
    user
    |> cast(attrs, [:agent_api_key, :agent_model])
    |> update_change(:agent_api_key, fn
      nil -> nil
      value -> String.trim(value)
    end)
    |> update_change(:agent_model, fn
      nil -> nil
      value -> String.trim(value)
    end)
    |> then(fn changeset ->
      case get_change(changeset, :agent_api_key) do
        "" -> put_change(changeset, :agent_api_key, nil)
        _other -> changeset
      end
    end)
    |> then(fn changeset ->
      case get_change(changeset, :agent_model) do
        "" -> put_change(changeset, :agent_model, nil)
        _other -> changeset
      end
    end)
    |> validate_length(:agent_api_key, max: 512)
    |> validate_agent_model()
  end

  @doc "Providers the settings page offers. Anything else req_llm ships is not."
  def agent_providers do
    ~w(openai anthropic google openrouter groq deepseek mistral xai
       cerebras fireworks_ai moonshot_ai zai ollama lmstudio vllm)
  end

  defp validate_agent_model(changeset) do
    case get_change(changeset, :agent_model) do
      nil ->
        changeset

      model ->
        case String.split(model, ":", parts: 2) do
          [provider, id] when id != "" ->
            if provider in agent_providers() do
              changeset
            else
              add_error(changeset, :agent_model, "uses an unsupported provider")
            end

          _other ->
            add_error(changeset, :agent_model, "must look like provider:model-id")
        end
    end
  end

  @doc "Whether the user brought their own provider key."
  def agent_key?(%__MODULE__{agent_api_key: key}), do: is_binary(key) and key != ""

  @doc "The user's own model spec, if they picked one."
  def agent_model(%__MODULE__{agent_model: model}), do: model

  @doc """
  Whether the user may use the admin surface.
  """
  def admin?(%__MODULE__{role: :admin}), do: true
  def admin?(_user), do: false

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Psc.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
