defmodule PscWeb.UserLive.Registration do
  use PscWeb, :live_view

  # SaladUI button/input/form called qualified (UIButton/UIInput/UIForm):
  # CoreComponents is global via html_helpers and defines the same names.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Form, as: UIForm
  alias PscWeb.Components.UI.Input, as: UIInput

  alias Psc.Accounts
  alias Psc.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-md">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate" novalidate>
          <UIForm.form_item>
            <UIForm.form_label field={@form[:email]}>Email</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@form[:email]}
                type="email"
                class="h-11 text-base sm:h-10 sm:text-sm"
                autocomplete="username"
                spellcheck="false"
                placeholder="you@example.com"
                required
                phx-mounted={JS.focus()}
              />
            </UIForm.form_control>
            <UIForm.form_message field={@form[:email]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@form[:password]}>Password</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@form[:password]}
                type="password"
                autocomplete="new-password"
                placeholder="At least 12 characters"
                class="h-11 text-base sm:h-10 sm:text-sm"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={@form[:password]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@form[:password_confirmation]}>
              Confirm password
            </UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@form[:password_confirmation]}
                type="password"
                autocomplete="new-password"
                placeholder="Repeat your password"
                class="h-11 text-base sm:h-10 sm:text-sm"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={@form[:password_confirmation]} />
          </UIForm.form_item>

          <UIButton.button phx-disable-with="Creating account..." class="w-full mt-2">
            Create an account
          </UIButton.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: PscWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{})

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        # No email confirmation: the account is confirmed immediately. The
        # one-time token URL is handed to the browser directly (no email) so
        # the Confirmation LiveView auto-logs the user in — register and done.
        user = Accounts.confirm_user!(user)
        token = Accounts.generate_login_token(user)

        {:noreply,
         socket
         |> put_flash(:info, "Account created — welcome!")
         |> redirect(to: ~p"/users/log-in/#{token}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
