defmodule PscWeb.UserLive.Login do
  use PscWeb, :live_view

  # SaladUI alert/button/input/form called qualified (UIAlert/UIButton/UIInput/UIForm):
  # CoreComponents is global via html_helpers and defines the same names.
  alias PscWeb.Components.UI.Alert, as: UIAlert
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Form, as: UIForm
  alias PscWeb.Components.UI.Input, as: UIInput

  alias Psc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-primary hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <UIAlert.alert :if={local_mail_adapter?()}>
          <UIAlert.alert_title>Local mail adapter</UIAlert.alert_title>
          <UIAlert.alert_description>
            You are running the local mail adapter. To see sent emails, visit <.link
              href="/dev/mailbox"
              class="underline"
            >the mailbox page</.link>.
          </UIAlert.alert_description>
        </UIAlert.alert>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <UIForm.form_item>
            <UIForm.form_control>
              <UIInput.input
                readonly={!!@current_scope}
                field={f[:email]}
                type="email"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />
            </UIForm.form_control>
            <UIForm.form_message field={f[:email]} />
          </UIForm.form_item>
          <UIButton.button class="w-full">
            Log in with email <span aria-hidden="true">→</span>
          </UIButton.button>
        </.form>

        <div class="my-4 flex items-center gap-3 text-xs text-base-content/50">
          <div class="h-px flex-1 bg-white/10"></div>
          or
          <div class="h-px flex-1 bg-white/10"></div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <UIForm.form_item>
            <UIForm.form_control>
              <UIInput.input
                readonly={!!@current_scope}
                field={f[:email]}
                type="email"
                autocomplete="username"
                spellcheck="false"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={f[:email]} />
          </UIForm.form_item>
          <UIForm.form_item>
            <UIForm.form_control>
              <UIInput.input
                field={@form[:password]}
                type="password"
                autocomplete="current-password"
                spellcheck="false"
              />
            </UIForm.form_control>
            <UIForm.form_message field={@form[:password]} />
          </UIForm.form_item>
          <UIButton.button
            class="w-full"
            name={@form[:remember_me].name}
            value="true"
          >
            Log in and stay logged in <span aria-hidden="true">→</span>
          </UIButton.button>
          <UIButton.button variant="secondary" class="w-full mt-2">
            Log in only this time
          </UIButton.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:psc, Psc.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
