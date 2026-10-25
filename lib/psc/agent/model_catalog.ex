defmodule Psc.Agent.ModelCatalog do
  @moduledoc """
  Model suggestions for a connection, and the "Test connection" probe.

  Two sources, on purpose:

    * `LLMDB`, the packaged model catalog that already ships with the agent
      runtime - instant, offline, no key. It seeds the datalist before a key
      has been tested.
    * the provider's own model listing - authoritative, and used to verify a
      key: a successful listing proves the credential and the endpoint.

  There is no single cross-provider standard. Most providers speak the OpenAI
  shape (`GET {base_url}/models` with a bearer token), Anthropic uses
  `x-api-key` plus a version header, and Google lists under `/v1beta/models`
  with the key as a query parameter. The catalog only ever sees model ids.
  """

  alias Psc.Agent.Connection

  @timeout_ms 10_000
  @max_models 500

  @doc "Offline suggestions for a provider, from the packaged catalog."
  def suggestions(provider) do
    case Connection.llm_db_provider(provider) do
      nil ->
        []

      id ->
        id
        |> LLMDB.models()
        |> Enum.map(& &1.id)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.take(@max_models)
    end
  rescue
    _error -> []
  end

  @doc """
  Lists the provider's models with the given key.

  Returns `{:ok, ids}` on success and `{:error, message}` with a sentence fit
  for the settings dialog otherwise. Also doubles as the connection test.

  Tests may install `config :psc, :model_catalog_fetcher` as a 3-arity function
  to replay a provider without a network call.
  """
  def fetch(provider, api_key, base_url) do
    case Application.get_env(:psc, :model_catalog_fetcher) do
      fun when is_function(fun, 3) -> fun.(provider, api_key, base_url)
      _other -> do_fetch(provider, api_key, base_url)
    end
  end

  defp do_fetch(provider, api_key, base_url) do
    adapter = Connection.adapter(provider)
    base_url = base_url || Connection.default_base_url(provider)

    cond do
      is_nil(base_url) ->
        {:error, "This provider has no default endpoint; set a base URL."}

      adapter == :google and blank?(api_key) ->
        {:error, "A key is required to list Google models."}

      adapter == :anthropic and blank?(api_key) ->
        {:error, "A key is required to list Anthropic models."}

      true ->
        base_url
        |> request(adapter, api_key)
        |> normalize(adapter)
    end
  end

  defp request(base_url, :google, api_key) do
    Req.get(base_url <> "/models",
      params: [key: api_key, pageSize: 1000],
      receive_timeout: @timeout_ms,
      retry: false
    )
  end

  defp request(base_url, :anthropic, api_key) do
    Req.get(base_url <> "/models",
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ],
      params: [limit: 1000],
      receive_timeout: @timeout_ms,
      retry: false
    )
  end

  defp request(base_url, :openai, api_key) do
    headers = if blank?(api_key), do: [], else: [{"authorization", "Bearer #{api_key}"}]

    Req.get(base_url <> "/models",
      headers: headers,
      receive_timeout: @timeout_ms,
      retry: false
    )
  end

  defp normalize({:ok, %{status: status, body: body}}, adapter) when status in 200..299 do
    case parse(adapter, body) do
      {:ok, []} -> {:error, "The provider returned an empty model list."}
      other -> other
    end
  end

  defp normalize({:ok, %{status: status}}, _adapter) do
    {:error, http_message(status)}
  end

  defp normalize({:error, %Req.TransportError{reason: :timeout}}, _adapter) do
    {:error, "The provider did not answer in time."}
  end

  defp normalize({:error, %Req.TransportError{reason: :econnrefused}}, _adapter) do
    {:error, "Nothing is listening at that base URL."}
  end

  defp normalize({:error, %Req.TransportError{reason: reason}}, _adapter) do
    {:error, "Could not reach the provider (#{reason})."}
  end

  defp normalize({:error, reason}, _adapter) do
    {:error, "Could not reach the provider (#{inspect(reason)})."}
  end

  defp http_message(401), do: "The provider rejected this key."
  defp http_message(403), do: "This key is not allowed to list models."
  defp http_message(404), do: "No model list at that base URL."
  defp http_message(429), do: "The provider is rate limiting this key."
  defp http_message(status), do: "The provider answered with HTTP #{status}."

  defp parse(_adapter, %{"data" => data}) when is_list(data) do
    {:ok, collect(data)}
  end

  defp parse(:google, %{"models" => models}) when is_list(models) do
    ids =
      models
      |> Enum.filter(&google_chat_model?/1)
      |> Enum.map(& &1["name"])
      |> Enum.map(&String.replace_prefix(&1, "models/", ""))
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.take(@max_models)

    {:ok, ids}
  end

  defp parse(_adapter, _body), do: {:error, "The provider returned an unexpected response."}

  defp collect(data) do
    data
    |> Enum.map(& &1["id"])
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.take(@max_models)
  end

  defp google_chat_model?(%{"supportedGenerationMethods" => methods}) when is_list(methods),
    do: "generateContent" in methods

  defp google_chat_model?(_model), do: true

  defp blank?(value), do: value in [nil, ""]
end
