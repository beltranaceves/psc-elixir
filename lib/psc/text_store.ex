defmodule Psc.TextStore do
  @moduledoc """
  The write-ahead log and folded snapshot machinery for collaborative text.

  Every collaborative text aggregate has the same shape: a row holding the
  folded `content` plus a `snapshot_seq` marker, and an event table holding
  the operations recorded since. Saving folds the pending operations into the
  row and prunes the events it covers; loading replays the events above the
  marker on top of the folded content.

  This module is that algorithm, once. An aggregate declares its shape through
  a small adapter module implementing this behaviour, and the algorithm is
  shared — not copied — by everything that needs it.

  ## Why the marker is floored

  Pruned events are gone, so `max(seq)` alone restarts at 1 after a prune and
  would place new events *below* the snapshot point, where the loader never
  replays them. Every sequence number is therefore floored at the store's
  `snapshot_seq`. See ADR-001 and ADR-002.
  """

  import Ecto.Query, warn: false

  alias Psc.Repo

  @doc """
  The schema module that holds the folded content and the snapshot marker.
  """
  @callback store() :: module

  @doc """
  The schema module that holds the event log.
  """
  @callback event() :: module

  @doc """
  The field on the event schema that points at the store.
  """
  @callback foreign_key() :: atom

  @doc """
  The field on the store schema that holds the folded content.
  """
  @callback content_field() :: atom

  @doc """
  The PubSub topic the operations are broadcast on.
  """
  @callback topic(id :: term) :: String.t()

  @doc """
  The tag of the broadcast message.

  The message is `{tag, user_id, operation, seq}`, or
  `{tag, user_id, client_id, operation, seq}` when the operation came from a
  known client. A consumer that listens to more than one kind of operation —
  the canvas editor listens to both the canvas's and a note's — needs to tell
  them apart; the client id lets a view ignore its own echo without ignoring
  another session of the same user.
  """
  @callback event_tag() :: atom

  @doc """
  The next sequence number for a store.

  Floored at the store's `snapshot_seq`: events at or below the snapshot are
  pruned, so `max(seq)` alone restarts at 1 after pruning and would place new
  events where the loader never replays them.
  """
  def next_sequence(adapter, id) do
    event = adapter.event()
    fk = adapter.foreign_key()

    max_event_seq =
      Repo.one(from(e in event, where: field(e, ^fk) == ^id, select: max(e.seq))) || 0

    snapshot_seq = snapshot_seq(adapter, id)

    max(max_event_seq, snapshot_seq) + 1
  end

  @doc """
  Load the content: the folded content plus the events recorded after it.

  The events are replayed in order, so the result is the same text every
  client would have converged to.
  """
  def load_content(adapter, id) do
    store = Repo.get!(adapter.store(), id)

    content = Map.get(store, adapter.content_field()) || ""
    snapshot_seq = store.snapshot_seq || 0

    events =
      from(e in adapter.event(),
        where: field(e, ^adapter.foreign_key()) == ^id and e.seq > ^snapshot_seq,
        order_by: [asc: e.seq]
      )
      |> Repo.all()

    Enum.reduce(events, content, &Psc.Text.apply_operation/2)
  end

  @doc """
  Fold the content into the store and prune the events it covers.

  Pruning happens only after the marker is durably stored, so a failed update
  can never drop events that are not yet represented in the saved content.
  """
  def save_content(adapter, id, content) do
    case Repo.get(adapter.store(), id) do
      nil -> {:error, :not_found}
      store -> do_save_content(adapter, id, content, store)
    end
  end

  defp do_save_content(adapter, id, content, store) do
    event = adapter.event()
    fk = adapter.foreign_key()

    # The seq the content is built through, floored at the stored marker.
    max_seq =
      max(
        Repo.one(from(e in event, where: field(e, ^fk) == ^id, select: max(e.seq))) || 0,
        store.snapshot_seq || 0
      )

    result =
      store
      |> adapter.store().changeset(%{
        adapter.content_field() => content,
        snapshot_seq: max_seq
      })
      |> Repo.update(stale_error_field: :base)

    with {:ok, _store} <- result do
      Repo.delete_all(from(e in event, where: field(e, ^fk) == ^id and e.seq <= ^max_seq))
    end

    result
  end

  @doc """
  Append an operation to the event log and broadcast it.

  Only the event is persisted here; the content is folded separately by
  `save_content/3` on the idle or periodic timer.

  `client_id` identifies the editing client (one LiveView process), not the
  user: the sender's own view is then the only one that can ignore its echo,
  while another tab of the same user still applies it.
  """
  def apply_operation(adapter, id, user_id, operation, client_id \\ nil) do
    seq = next_sequence(adapter, id)
    event = adapter.event()

    event_attrs = %{
      adapter.foreign_key() => id,
      operation: operation,
      seq: seq,
      user_id: user_id
    }

    case Repo.insert(event.changeset(struct(event), event_attrs)) do
      {:ok, _event} ->
        broadcast(adapter, id, user_id, operation, seq, client_id)
        {:ok, seq}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Broadcast an operation to everyone subscribed to the store.
  """
  def broadcast(adapter, id, user_id, operation, seq) do
    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      adapter.topic(id),
      {adapter.event_tag(), user_id, operation, seq}
    )
  end

  @doc """
  Broadcast an operation from a known client.

  The tag carries the sender's client id so a subscriber can ignore the echo
  of its own edit without ignoring another session of the same user.
  """
  def broadcast(adapter, id, user_id, operation, seq, nil) do
    broadcast(adapter, id, user_id, operation, seq)
  end

  def broadcast(adapter, id, user_id, operation, seq, client_id) do
    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      adapter.topic(id),
      {adapter.event_tag(), user_id, client_id, operation, seq}
    )
  end

  @doc """
  The number of operations not yet folded into the content.
  """
  def pending_event_count(adapter, id) do
    snapshot_seq = snapshot_seq(adapter, id)
    event = adapter.event()
    fk = adapter.foreign_key()

    Repo.one(
      from(e in event,
        where: field(e, ^fk) == ^id and e.seq > ^snapshot_seq,
        select: count(e.id)
      )
    ) || 0
  end

  @doc """
  Delete events already folded into the saved content.

  Pruning normally happens on every save, but it only ever touches stores
  that are edited again — one abandoned before its first save keeps its tail
  of events forever. This sweeps every row at or below its owner's
  `snapshot_seq`. Returns the number of deleted rows.
  """
  def sweep_folded_events(adapter) do
    event = adapter.event()
    fk = adapter.foreign_key()
    store = adapter.store()

    # An event is covered when it is at or below the snapshot_seq of the
    # store it belongs to. The stores are joined in as a subquery because the
    # schemas are adapter-supplied.
    {deleted, _} =
      from(e in event)
      |> join(
        :inner,
        [e],
        s in subquery(from(s in store, select: %{id: s.id, seq: s.snapshot_seq})),
        on: field(e, ^fk) == s.id
      )
      |> where([e, s], e.seq <= s.seq)
      |> Repo.delete_all()

    deleted
  end

  defp snapshot_seq(adapter, id) do
    Repo.one(from(s in adapter.store(), where: s.id == ^id, select: s.snapshot_seq)) || 0
  end
end
