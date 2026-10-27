defmodule PscWeb.Admin.ApiKeyLive do
  @moduledoc """
  Administration of the provider keys that power the canvas agent.

  A key is an `agent_connections` row owned by an account: the owner sees it in
  Settings → Agent connections and can rotate or delete it there. This page
  exists so an admin can hand an account a key it did not have to bring itself.

  Keys are write-only end to end. The create and rotate forms are the only
  places one is typed, the changeset never leaves the request, and the table
  renders `key_hint` ("…ab12") instead of the value.
  """

  use PscWeb, :live_view

  alias Psc.Accounts
  alias Psc.Agent.Connection
  alias Psc.Agent.Connections
  alias Psc.Agent.ModelCatalog

  @fields ["name", "provider", "model_id", "api_key", "base_url"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API keys")
     |> assign(:rotating, nil)
     |> assign(:rotate_form, nil)
     |> assign(:models, [])
     |> assign(:user_error, nil)
     |> assign(:form, new_form())
     |> reload()}
  end

  @impl true
  def handle_event("validate", %{"key" => params}, socket) do
    previous_provider = socket.assigns.form[:provider].value
    user = account(params["user_id"])

    socket =
      socket
      |> assign(:form, key_form(changeset_for(user, params)))
      |> assign(:user_error, nil)
      |> maybe_update_models(previous_provider, params["provider"])

    {:noreply, socket}
  end

  def handle_event("save", %{"key" => params}, socket) do
    user = account(params["user_id"])
    changeset = changeset_for(user, params)

    if user && changeset.valid? do
      case Connections.create(user, attrs(params, user)) do
        {:ok, _connection} ->
          {:noreply,
           socket
           |> assign(:form, new_form())
           |> assign(:user_error, nil)
           |> reload()
           |> put_flash(:success, "Key issued for #{user.email}.")}

        {:error, :limit} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "#{user.email} already has the maximum of #{Connections.max_per_user()} keys."
           )}

        {:error, failed} ->
          {:noreply, socket |> assign(:form, key_form(failed)) |> assign(:user_error, nil)}
      end
    else
      {:noreply,
       socket
       |> assign(:form, key_form(changeset))
       |> assign(:user_error, if(is_nil(user), do: "Choose the account this key belongs to."))}
    end
  end

  def handle_event("rotate", %{"id" => id}, socket) do
    case Connections.admin_get(id) do
      nil ->
        {:noreply, socket |> clear_rotate() |> put_flash(:error, "That key is no longer there.")}

      connection ->
        {:noreply,
         assign(socket,
           rotating: connection,
           rotate_form: rotate_form_for(Connection.changeset(connection, %{}))
         )}
    end
  end

  def handle_event("cancel_rotate", _params, socket), do: {:noreply, clear_rotate(socket)}

  def handle_event("rotate_key", %{"key_id" => id, "rotate" => params}, socket) do
    case Connections.admin_get(id) do
      nil ->
        {:noreply, socket |> clear_rotate() |> put_flash(:error, "That key is no longer there.")}

      connection ->
        changeset = rotate_changeset(connection, params["api_key"])

        if changeset.valid? do
          {:ok, _connection} = Connections.update(connection, %{"api_key" => params["api_key"]})

          {:noreply,
           socket
           |> clear_rotate()
           |> reload()
           |> put_flash(:success, "Key rotated for #{connection.user.email}.")}
        else
          {:noreply, assign(socket, :rotate_form, rotate_form_for(changeset))}
        end
    end
  end

  def handle_event("set_default", %{"id" => id}, socket) do
    with %Connection{} = connection <- Connections.admin_get(id),
         %Accounts.User{} = user <- Accounts.get_user(connection.user_id),
         {:ok, _user} <- Connections.set_default(user, connection) do
      {:noreply,
       socket
       |> reload()
       |> put_flash(:success, "#{connection.name} is now the default for #{user.email}.")}
    else
      _other ->
        {:noreply, socket |> reload() |> put_flash(:error, "That key is no longer there.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Connections.admin_get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That key is no longer there.")}

      connection ->
        {:ok, _result} = Connections.delete(connection)

        {:noreply,
         socket
         |> clear_rotate()
         |> reload()
         |> put_flash(:success, "Key deleted for #{connection.user.email}.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      live_resource={nil}
      current_url={Map.get(assigns, :current_url)}
      sidebar_open={Map.get(assigns, :sidebar_open, true)}
      sidebar_section_states={Map.get(assigns, :sidebar_section_states, %{})}
      preferences_manifest={Map.get(assigns, :preferences_manifest)}
    >
      <div id="admin-api-keys" class="mx-auto w-full max-w-7xl space-y-8 p-4 sm:p-6 lg:p-8">
        <header>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">API keys</h1>

          <p class="mt-1 max-w-3xl text-sm text-base-content/60">
            Provider keys for the canvas agent. A key belongs to an account, so issuing one here
            turns the Agent tab on for that person without them having to bring their own. Keys
            are write-only: only the last four characters are ever shown.
          </p>
        </header>

        <section
          aria-label="Issue a key"
          class="rounded-xl border border-base-content/10 bg-base-200 p-4 sm:p-5"
        >
          <h2 class="text-sm font-medium text-base-content">Issue a key</h2>

          <p class="mt-1 text-sm text-base-content/60">
            The account must already exist — accounts are created by registration or by the
            <code class="rounded bg-base-content/10 px-1">ADMIN_EMAILS</code>
            bootstrap. Usage is billed by the provider to whoever owns the key.
          </p>

          <.form
            for={@form}
            id="api-key-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4 grid gap-3 sm:grid-cols-2"
          >
            <div>
              <.input
                field={@form[:user_id]}
                type="select"
                label="Account"
                prompt="Choose an account…"
                options={account_options(@accounts)}
              />
              <p :if={@user_error} id="api-key-account-error" class="text-sm text-error">
                {@user_error}
              </p>
            </div>
            <.input
              field={@form[:provider]}
              type="select"
              label="Provider"
              prompt="Choose a provider…"
              options={provider_options()}
            />
            <.input
              field={@form[:model_id]}
              type="text"
              label="Model"
              list="api-key-models"
              placeholder="e.g. gpt-4.1-mini"
              autocomplete="off"
            />
            <datalist id="api-key-models">
              <option :for={model <- @models} value={model} />
            </datalist>

            <.input
              field={@form[:api_key]}
              type="password"
              label="API key"
              placeholder="Paste the provider key"
              autocomplete="new-password"
            />
            <.input
              field={@form[:name]}
              type="text"
              label="Label (optional)"
              placeholder="Defaults to the provider name"
            />
            <.input
              field={@form[:base_url]}
              type="text"
              label="Endpoint (optional)"
              placeholder="Only for self-hosted servers or gateways"
            />
            <div class="sm:col-span-2">
              <button
                type="submit"
                phx-disable-with="Issuing…"
                class="inline-flex items-center gap-2 rounded-lg bg-primary px-3.5 py-2 text-sm font-medium text-primary-content transition-opacity hover:opacity-90"
              >
                <.icon name="hero-plus" class="size-4" /> Issue key
              </button>
            </div>
          </.form>
        </section>

        <section aria-label="Issued keys" class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/40">
              Issued keys
            </h2>

            <p id="api-key-count" class="text-xs text-base-content/50">
              {plural(length(@connections), "key")} across {plural(length(@accounts), "account")}
            </p>
          </div>

          <p
            :if={@connections == []}
            class="rounded-xl border border-dashed border-base-content/20 bg-base-200/50 p-5 text-center text-sm text-base-content/60"
          >
            No keys yet. Every account brings its own provider key in Settings; issue one here to
            let someone try the agent without one.
          </p>

          <div
            :if={@connections != []}
            class="overflow-x-auto rounded-xl border border-base-content/10 bg-base-200"
          >
            <table class="w-full text-left text-sm">
              <thead class="border-b border-base-content/10 text-xs uppercase tracking-wide text-base-content/50">
                <tr>
                  <th class="px-4 py-2.5 font-medium">Account</th>

                  <th class="px-4 py-2.5 font-medium">Label</th>

                  <th class="px-4 py-2.5 font-medium">Provider</th>

                  <th class="px-4 py-2.5 font-medium">Model</th>

                  <th class="px-4 py-2.5 font-medium">Key</th>

                  <th class="px-4 py-2.5 font-medium">Last used</th>

                  <th class="px-4 py-2.5 text-right font-medium">Actions</th>
                </tr>
              </thead>

              <tbody class="divide-y divide-base-content/10">
                <.key_row
                  :for={connection <- @connections}
                  connection={connection}
                  rotating?={@rotating && @rotating.id == connection.id}
                  form={@rotate_form}
                />
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  attr :connection, :map, required: true
  attr :rotating?, :boolean, default: false
  attr :form, :any, default: nil

  defp key_row(assigns) do
    ~H"""
    <tr id={"api-key-#{@connection.id}"} class="align-top">
      <td class="px-4 py-2.5">
        <span class="block text-base-content">{@connection.user_email}</span>
        <span :if={@connection.default?} class="text-xs text-primary">default</span>
      </td>

      <td class="px-4 py-2.5 text-base-content/80">{@connection.name}</td>

      <td class="px-4 py-2.5 text-base-content/70">{@connection.provider_label}</td>

      <td class="px-4 py-2.5">
        <span class="block font-mono text-xs text-base-content/80">{@connection.model_id}</span>
        <span :if={@connection.base_url} class="block text-xs text-base-content/45">
          {@connection.base_url}
        </span>
      </td>

      <td class="px-4 py-2.5 font-mono text-xs text-base-content/70">
        {@connection.key_hint || "—"}
      </td>

      <td class="px-4 py-2.5 text-xs text-base-content/60">
        {relative_time(@connection.last_used_at)}
      </td>

      <td class="px-4 py-2.5">
        <div class="flex items-center justify-end gap-1">
          <button
            :if={!@connection.default?}
            type="button"
            phx-click="set_default"
            phx-value-id={@connection.id}
            title="Make this the account's default"
            aria-label={"Make #{@connection.name} the default for #{@connection.user_email}"}
            class="rounded-lg p-1.5 text-base-content/50 transition-colors hover:bg-base-content/10 hover:text-base-content"
          >
            <.icon name="hero-star" class="size-4" />
          </button>

          <button
            type="button"
            phx-click="rotate"
            phx-value-id={@connection.id}
            title="Rotate the key"
            aria-label={"Rotate the key for #{@connection.user_email}"}
            class="rounded-lg p-1.5 text-base-content/50 transition-colors hover:bg-base-content/10 hover:text-base-content"
          >
            <.icon name="hero-key" class="size-4" />
          </button>

          <button
            type="button"
            phx-click="delete"
            phx-value-id={@connection.id}
            data-confirm={"Delete #{@connection.name} for #{@connection.user_email}? The Agent tab stops working for them unless they have another key."}
            title="Delete the key"
            aria-label={"Delete the key for #{@connection.user_email}"}
            class="rounded-lg p-1.5 text-base-content/50 transition-colors hover:bg-error/10 hover:text-error"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>
      </td>
    </tr>

    <tr :if={@rotating?} id={"rotate-key-#{@connection.id}"} class="bg-base-content/5">
      <td colspan="7" class="px-4 py-3">
        <.form for={@form} id={"rotate-key-form-#{@connection.id}"} phx-submit="rotate_key">
          <input type="hidden" name="key_id" value={@connection.id} />
          <div class="flex flex-wrap items-end gap-3">
            <div class="min-w-56 flex-1">
              <.input
                field={@form[:api_key]}
                type="password"
                label={"New key for #{@connection.user_email}"}
                placeholder="Paste the replacement key"
                autocomplete="new-password"
              />
            </div>

            <button
              type="submit"
              phx-disable-with="Rotating…"
              class="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-primary-content transition-opacity hover:opacity-90"
            >
              Save new key
            </button>

            <button
              type="button"
              phx-click="cancel_rotate"
              class="rounded-lg border border-base-content/15 px-3 py-1.5 text-sm font-medium text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content"
            >
              Cancel
            </button>
          </div>
        </.form>
      </td>
    </tr>
    """
  end

  defp new_form do
    Connection.changeset(%Connection{}, %{})
    |> key_form()
  end

  defp key_form(changeset), do: to_form(%{changeset | action: :validate}, as: :key)
  defp rotate_form_for(changeset), do: to_form(%{changeset | action: :validate}, as: :rotate)

  defp reload(socket) do
    assign(socket,
      connections: Connections.admin_summaries(),
      accounts: Accounts.list_users() |> Enum.sort_by(& &1.email)
    )
  end

  defp clear_rotate(socket), do: assign(socket, rotating: nil, rotate_form: nil)

  defp changeset_for(nil, params) do
    Connection.changeset(%Connection{}, Map.take(params, @fields))
  end

  defp changeset_for(user, params) do
    %Connection{user_id: user.id}
    |> Connection.changeset(attrs(params, user))
    |> Ecto.Changeset.put_change(:user_id, user.id)
  end

  defp rotate_changeset(connection, key) do
    if blank?(key) do
      connection
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:api_key, "Enter the new key")
    else
      Connection.changeset(connection, %{"api_key" => key})
    end
  end

  defp attrs(params, user) do
    params
    |> Map.take(@fields)
    |> put_default_name(user)
  end

  defp put_default_name(attrs, user) do
    case attrs["name"] do
      name when name in [nil, ""] ->
        Map.put(attrs, "name", Connections.suggested_name(user.id, attrs["provider"]))

      _name ->
        attrs
    end
  end

  defp maybe_update_models(socket, previous, provider) do
    if provider == previous do
      socket
    else
      assign(socket, :models, ModelCatalog.suggestions(provider))
    end
  end

  defp account(id) when is_binary(id) do
    case Integer.parse(id) do
      {user_id, ""} -> Accounts.get_user(user_id)
      _other -> nil
    end
  end

  defp account(_id), do: nil

  defp account_options(accounts) do
    Enum.map(accounts, fn user ->
      label = if user.role == :admin, do: "#{user.email} (admin)", else: user.email
      {label, user.id}
    end)
  end

  defp provider_options do
    Enum.map(Connection.providers(), &{&1.label, &1.id})
  end

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(count, noun), do: "#{count} #{noun}s"

  defp blank?(value), do: value in [nil, ""]

  defp relative_time(nil), do: "never"
  defp relative_time(at), do: relative_time(DateTime.diff(DateTime.utc_now(), at), at)
  defp relative_time(seconds, _at) when seconds < 60, do: "just now"
  defp relative_time(seconds, _at) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp relative_time(seconds, _at) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"
  defp relative_time(seconds, _at) when seconds < 2_592_000, do: "#{div(seconds, 86_400)}d ago"
  defp relative_time(_seconds, at), do: Calendar.strftime(at, "%d %b %Y")
end
