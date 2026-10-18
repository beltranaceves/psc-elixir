defmodule PscWeb.UserLive.Login do
  use PscWeb, :live_view

  # SaladUI button/input/form called qualified (UIButton/UIInput/UIForm):
  # CoreComponents is global via html_helpers and defines the same names.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Form, as: UIForm
  alias PscWeb.Components.UI.Helpers, as: UIHelpers
  alias PscWeb.Components.UI.Input, as: UIInput

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

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          novalidate
        >
          <UIForm.form_item>
            <UIForm.form_label field={f[:email]}>Email</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                readonly={!!@current_scope}
                field={f[:email]}
                type="email"
                autocomplete="username"
                spellcheck="false"
                placeholder="you@example.com"
                required
              />
            </UIForm.form_control>
            <UIForm.form_message field={f[:email]} />
          </UIForm.form_item>
          <UIForm.form_item>
            <UIForm.form_label field={f[:password]}>Password</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={f[:password]}
                type="password"
                autocomplete="current-password"
                spellcheck="false"
                placeholder="Your password"
              />
            </UIForm.form_control>
            <UIForm.form_message field={f[:password]} />
          </UIForm.form_item>
          <UIButton.button
            class="w-full gap-2 mt-3"
            name={@form[:remember_me].name}
            value="true"
          >
            Log in <span aria-hidden="true">→</span>
          </UIButton.button>
          <.link
            :if={is_nil(@current_scope)}
            id="sign_up_link"
            navigate={~p"/users/register"}
            class={[UIHelpers.button_variant(%{variant: "secondary"}), "mt-2 w-full"]}
          >
            Sign up
          </.link>
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

    form = to_form(login_changeset(%{"email" => email}), as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = params |> login_changeset() |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  @impl true
  def handle_event("submit_password", %{"user" => params}, socket) do
    changeset = login_changeset(params)

    if changeset.valid? do
      # Hand over to the session controller, which owns the generic
      # "Invalid email or password" flash (no user enumeration).
      {:noreply, assign(socket, :trigger_submit, true)}
    else
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  # Login only checks presence and email shape: whether the account exists is
  # deliberately left to the controller's generic error message.
  defp login_changeset(params) do
    changeset =
      {%{}, %{email: :string, password: :string}}
      |> Ecto.Changeset.cast(params, [:email, :password])
      |> Ecto.Changeset.validate_required([:email, :password])

    case Ecto.Changeset.get_change(changeset, :email) do
      blank when blank in [nil, ""] ->
        changeset

      _email ->
        Ecto.Changeset.validate_format(changeset, :email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
          message: "must have the @ sign and no spaces"
        )
    end
  end
end
