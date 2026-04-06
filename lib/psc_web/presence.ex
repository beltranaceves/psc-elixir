defmodule PscWeb.Presence do
  use Phoenix.Presence,
    otp_app: :psc,
    pubsub_server: Psc.PubSub
end
