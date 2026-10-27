# Promotes (or creates) the accounts listed in ADMIN_EMAILS — the same step the
# release task runs on every boot, on its own so a fresh development database
# does not need a full `mix run -e "Psc.Release.setup()"`.
#
#     set ADMIN_EMAILS=you@example.com && mix run priv/repo/bootstrap_admins.exs
#
# ADMIN_PASSWORD is only needed for addresses that have no account yet, and it
# must satisfy the registration rules (at least 12 characters). An existing
# account is promoted in place and keeps its password.
#
# Idempotent: an address that is already an admin is left alone.

{promoted, created, skipped} = Psc.Accounts.bootstrap_admins()

IO.puts(
  "Admins: #{promoted} promoted, #{created} created, #{length(skipped)} skipped" <>
    if(skipped == [], do: "", else: " (#{Enum.join(skipped, ", ")} — set ADMIN_PASSWORD)")
)
