defmodule Psc.Repo do
  use Ecto.Repo,
    otp_app: :psc,
    adapter: Ecto.Adapters.Postgres
end
