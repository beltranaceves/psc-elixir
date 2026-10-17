defmodule PscWeb.UserLive.Confirmation do
  use PscWeb, :live_view

  # SaladUI button called qualified (UIButton): CoreComponents is global
  # via html_helpers and also defines button/1.
  alias PscWeb.Components.UI.Button, as: UIButton

  alias Psc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>Welcome {@user.email}</.header>
        </div>

        <.form
          for={@form}
          id="login_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <UIButton.button phx-disable-with="Logging in..." class="w-full">
              Log in
            </UIButton.button>
          <% else %>
            <UIButton.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Logging in..."
              class="w-full"
            >
              Keep me logged in on this device
            </UIButton.button>
            <UIButton.button
              variant="secondary"
              phx-disable-with="Logging in..."
              class="w-full mt-2"
            >
              Log me in only this time
            </UIButton.button>
          <% end %>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_magic_link_token(token) do
      %{confirmed_at: confirmed_at} = user when not is_nil(confirmed_at) ->
        form = to_form(%{"token" => token}, as: "user")

        {:ok,
         assign(socket,
           user: user,
           form: form,
           # Auto-submit the login form on mount so the token URL signs the
           # user in directly — zero clicks after registration.
           trigger_submit: true
         ), temporary_assigns: [form: nil]}

      _ ->
        # Invalid, expired, or unconfirmed: accounts are confirmed at
        # registration in this app, so anything else is not a usable link.
        {:ok,
         socket
         |> put_flash(:error, "Magic link is invalid or it has expired.")
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
