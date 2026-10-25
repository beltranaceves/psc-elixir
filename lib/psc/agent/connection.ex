defmodule Psc.Agent.Connection do
  @moduledoc """
  A saved provider pin: a name, a provider, an API key and a model.

  The key is write-only: it is redacted in inspections, never rendered back by
  the interface, and the LiveViews only ever see `summary/2` maps, which carry
  `key_hint` ("…ab12") instead. `base_url` lets self-hosted servers and
  OpenAI-compatible gateways be used; `models` is the last model list fetched
  from the provider, used for autocomplete.

  Two providers are not plain bearer-token APIs (`anthropic` sends `x-api-key`
  and a version header, `google` takes the key as a query parameter); the
  adapter in `Psc.Agent.ModelCatalog` is what tells them apart.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @providers [
    %{
      id: "openai",
      label: "OpenAI",
      adapter: :openai,
      base_url: "https://api.openai.com/v1",
      key_placeholder: "sk-…",
      model_placeholder: "gpt-4.1-mini",
      llm_db: :openai
    },
    %{
      id: "anthropic",
      label: "Anthropic",
      adapter: :anthropic,
      base_url: "https://api.anthropic.com/v1",
      key_placeholder: "sk-ant-…",
      model_placeholder: "claude-haiku-4-5",
      llm_db: :anthropic
    },
    %{
      id: "google",
      label: "Google Gemini",
      adapter: :google,
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      key_placeholder: "AIza…",
      model_placeholder: "gemini-2.0-flash",
      llm_db: :google
    },
    %{
      id: "openrouter",
      label: "OpenRouter",
      adapter: :openai,
      base_url: "https://openrouter.ai/api/v1",
      key_placeholder: "sk-or-…",
      model_placeholder: "anthropic/claude-haiku-4.5",
      llm_db: :openrouter
    },
    %{
      id: "groq",
      label: "Groq",
      adapter: :openai,
      base_url: "https://api.groq.com/openai/v1",
      key_placeholder: "gsk_…",
      model_placeholder: "llama-3.3-70b-versatile",
      llm_db: :groq
    },
    %{
      id: "deepseek",
      label: "DeepSeek",
      adapter: :openai,
      base_url: "https://api.deepseek.com",
      key_placeholder: "sk-…",
      model_placeholder: "deepseek-chat",
      llm_db: :deepseek
    },
    %{
      id: "mistral",
      label: "Mistral",
      adapter: :openai,
      base_url: "https://api.mistral.ai/v1",
      key_placeholder: "…",
      model_placeholder: "mistral-small-latest",
      llm_db: :mistral
    },
    %{
      id: "xai",
      label: "xAI",
      adapter: :openai,
      base_url: "https://api.x.ai/v1",
      key_placeholder: "xai-…",
      model_placeholder: "grok-4",
      llm_db: :xai
    },
    %{
      id: "cerebras",
      label: "Cerebras",
      adapter: :openai,
      base_url: "https://api.cerebras.ai/v1",
      key_placeholder: "csk-…",
      model_placeholder: "llama-3.3-70b",
      llm_db: :cerebras
    },
    %{
      id: "fireworks_ai",
      label: "Fireworks",
      adapter: :openai,
      base_url: "https://api.fireworks.ai/inference/v1",
      key_placeholder: "fw_…",
      model_placeholder: "accounts/fireworks/models/llama-v3p3-70b-instruct",
      llm_db: :fireworks_ai
    },
    %{
      id: "moonshot_ai",
      label: "Moonshot AI",
      adapter: :openai,
      base_url: "https://api.moonshot.ai/v1",
      key_placeholder: "sk-…",
      model_placeholder: "kimi-k2",
      llm_db: nil
    },
    %{
      id: "zai",
      label: "Z.AI",
      adapter: :openai,
      base_url: "https://api.z.ai/api/paas/v4",
      key_placeholder: "…",
      model_placeholder: "glm-4.6",
      llm_db: :zai
    },
    %{
      id: "ollama",
      label: "Ollama",
      adapter: :openai,
      base_url: "http://localhost:11434/v1",
      key_placeholder: "not required",
      model_placeholder: "llama3.1",
      needs_key: false,
      llm_db: nil
    },
    %{
      id: "lmstudio",
      label: "LM Studio",
      adapter: :openai,
      base_url: "http://localhost:1234/v1",
      key_placeholder: "not required",
      model_placeholder: "local-model",
      needs_key: false,
      llm_db: :lmstudio
    },
    %{
      id: "vllm",
      label: "vLLM",
      adapter: :openai,
      base_url: "http://localhost:8000/v1",
      key_placeholder: "not required",
      model_placeholder: "your-served-model",
      needs_key: false,
      llm_db: nil
    }
  ]

  @max_name_length 40
  @max_model_length 120
  @max_base_url_length 255
  @max_key_length 512
  @min_key_length 8

  schema "agent_connections" do
    field :name, :string
    field :provider, :string
    field :model_id, :string
    field :api_key, :string, redact: true
    field :key_hint, :string
    field :base_url, :string
    field :models, {:array, :string}, default: []
    field :models_fetched_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec

    belongs_to :user, Psc.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The providers the settings page offers, in display order."
  def providers, do: @providers

  def provider_ids, do: Enum.map(@providers, & &1.id)

  def provider_meta(provider), do: Enum.find(@providers, &(&1.id == provider))

  def provider_label(provider) do
    case provider_meta(provider) do
      %{label: label} -> label
      nil -> provider
    end
  end

  @doc "The API surface the model list lives behind."
  def adapter(provider) do
    case provider_meta(provider) do
      %{adapter: adapter} -> adapter
      nil -> :openai
    end
  end

  @doc "Providers a key is required for; self-hosted servers usually have none."
  def needs_key?(provider) do
    case provider_meta(provider) do
      %{needs_key: false} -> false
      _other -> true
    end
  end

  def default_base_url(provider) do
    case provider_meta(provider) do
      %{base_url: base_url} -> base_url
      nil -> nil
    end
  end

  def llm_db_provider(provider) do
    case provider_meta(provider) do
      %{llm_db: id} -> id
      nil -> nil
    end
  end

  @doc "The `provider:model` spec the turn passes to req_llm."
  def model_spec(%__MODULE__{provider: provider, model_id: model_id}),
    do: "#{provider}:#{model_id}"

  @doc "Masks a key for display: never the whole value, at most the last four."
  def key_hint(nil), do: nil

  def key_hint(key) when is_binary(key) do
    trimmed = String.trim(key)

    if String.length(trimmed) <= 8 do
      "saved"
    else
      "…" <> String.slice(trimmed, -4, 4)
    end
  end

  @doc """
  The map the LiveViews may see. Deliberately has no `api_key` key: anything
  rendered or assigned to the client is derived from this.
  """
  def summary(%__MODULE__{} = connection, opts \\ []) do
    %{
      id: connection.id,
      name: connection.name,
      provider: connection.provider,
      provider_label: provider_label(connection.provider),
      model_id: connection.model_id,
      model_spec: model_spec(connection),
      key_hint: connection.key_hint,
      base_url: connection.base_url,
      last_used_at: connection.last_used_at,
      default?: Keyword.get(opts, :default?, false)
    }
  end

  @doc """
  Builds a connection. `:models` and `:models_fetched_at` are never cast from
  request params; the context sets them from a successful fetch.
  """
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:name, :provider, :model_id, :api_key, :base_url])
    |> update_change(:name, &trim/1)
    |> update_change(:model_id, &trim/1)
    |> update_change(:api_key, &blank_to_nil/1)
    |> update_change(:base_url, &normalize_base_url/1)
    |> put_key_hint()
    |> validate_required([:name, :provider, :model_id])
    |> validate_length(:name, max: @max_name_length)
    |> validate_length(:model_id, max: @max_model_length)
    |> validate_format(:model_id, ~r/^[^\s:]+$/, message: "cannot contain spaces or ':'")
    |> validate_inclusion(:provider, provider_ids())
    |> validate_key()
    |> validate_base_url()
    |> unique_constraint(:name,
      name: :agent_connections_user_id_name_index,
      message: "already exists"
    )
  end

  defp put_key_hint(changeset) do
    case get_change(changeset, :api_key) do
      key when is_binary(key) -> put_change(changeset, :key_hint, key_hint(key))
      _other -> changeset
    end
  end

  defp validate_key(changeset) do
    provider = get_field(changeset, :provider)
    key = get_field(changeset, :api_key)

    cond do
      needs_key?(provider) and blank?(key) ->
        add_error(changeset, :api_key, "is required for this provider")

      blank?(key) ->
        changeset

      true ->
        validate_length(changeset, :api_key,
          min: @min_key_length,
          max: @max_key_length
        )
    end
  end

  defp validate_base_url(changeset) do
    case get_field(changeset, :base_url) do
      nil ->
        changeset

      _base_url ->
        changeset
        |> validate_length(:base_url, max: @max_base_url_length)
        |> validate_format(:base_url, ~r/^https?:\/\/\S+$/,
          message: "must start with http:// or https://"
        )
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp normalize_base_url(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      url -> String.trim_trailing(url, "/")
    end
  end

  defp normalize_base_url(value), do: value

  defp blank?(value), do: value in [nil, ""]
end
