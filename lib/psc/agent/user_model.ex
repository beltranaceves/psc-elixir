defmodule Psc.Agent.UserModel do
  @moduledoc """
  Applies the user's own `provider:model_id` to each ReAct turn.

  `CanvasAgent` binds `model: :default` at compile time and `ask/3` has no
  per-request `model:` option, so the model is swapped through the documented
  request-transformer seam instead. The spec travels in the tool context, which
  this callback receives on every turn.

  Doing it this way - rather than rewriting the global `model_aliases` around a
  call - keeps concurrent users on their own providers.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  @impl true
  def transform_request(_request, _state, _config, context) do
    overrides =
      %{
        # Jido injects `previous_response_id` into provider options for every
        # streaming turn, after the per-request options are merged. ReqLLM then
        # validates that map against the provider schema, and providers such as
        # OpenRouter reject the unknown key:
        #
        #   unknown options [:previous_response_id], keys_path: [:provider_options]
        #
        # The transformer runs after the injection, and `llm_opts` is merged
        # key-by-key, so an empty `provider_options` replaces the map and drops
        # it. We never set provider options of our own, so nothing is lost.
        llm_opts: [provider_options: []]
      }

    case Map.get(context, :model) do
      spec when is_binary(spec) and spec != "" -> {:ok, Map.put(overrides, :model, spec)}
      _other -> {:ok, overrides}
    end
  end
end
