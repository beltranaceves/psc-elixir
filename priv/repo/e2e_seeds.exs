# Seeds a confirmed user for E2E browser tests (Playwright).
#
# Idempotent: safe to run multiple times.
#
# Run with:
#   MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs

alias Psc.Accounts
alias Psc.Accounts.User
alias Psc.Repo

email = "e2e@example.com"
password = "e2e-password-123"

user =
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: email})
      user

    user ->
      user
  end

# Confirm the account so the email-confirmation flow is bypassed.
user = user |> User.confirm_changeset() |> Repo.update!()

# Ensure a password is set so the password login form works.
if is_nil(user.hashed_password) do
  {:ok, user} = Accounts.update_user_password(user, %{password: password})
end

IO.puts("E2E user ready: #{user.email}")
