# Seeds a confirmed user for E2E browser tests (Playwright).
#
# Idempotent: safe to run multiple times.
#
# Run with:
#   MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs

alias Psc.Accounts
alias Psc.Accounts.User
alias Psc.Repo

ensure_user = fn email, password ->
  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        # registration_changeset requires a password (>= 12 chars) and hashes it;
        # password_confirmation is optional in the changeset (required: false).
        {:ok, user} = Accounts.register_user(%{email: email, password: password})
        user

      user ->
        user
    end

  # Confirm the account so the email-confirmation flow is bypassed.
  user = user |> User.confirm_changeset() |> Repo.update!()

  # Ensure a password is set so the password login form works.
  if is_nil(user.hashed_password) do
    {:ok, _user} = Accounts.update_user_password(user, %{password: password})
  end

  IO.puts("E2E user ready: #{user.email}")
  user
end

# Primary account (logged in via tests/auth.setup.ts storage state).
primary = ensure_user.("e2e@example.com", "e2e-password-123")

# The admin surface needs an administrator; the primary E2E user is it.
{:ok, _admin} = Accounts.promote_admin(primary)

# The Agent tab's composer only enables with a saved provider connection. The
# E2E specs that visit the tab render its shell and open its menus; they never
# send a turn, so a placeholder key is enough and no request leaves the box.
if Psc.Agent.Connections.list(primary.id) == [] do
  {:ok, _connection} =
    Psc.Agent.Connections.create(primary, %{
      "name" => "E2E model",
      "provider" => "openai",
      "api_key" => "sk-e2e-not-a-real-key",
      "model_id" => "gpt-4.1-mini"
    })
end

IO.puts("E2E agent connection ready")

# The release tasks seed the built-in templates on boot. The E2E database is
# reset between runs, so seed them here too — the picker shows them.
{created, _present} = Psc.Canvas.seed_builtin_templates()
IO.puts("E2E built-in templates created: #{created}")

# Second account for multiplayer/collaboration tests (logged in per-test
# in a separate browser context — see tests/canvas.spec.ts).
ensure_user.("e2e2@example.com", "e2e2-password-123")
