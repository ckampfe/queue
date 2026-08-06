defmodule Queue do
  @moduledoc """
  A shared mutable queue, optimized for bulk operations.
  """

  use Rustler,
    otp_app: :queue,
    crate: "queue",
    mode: if(Mix.env() in [:prod, :test], do: :release, else: :debug)

  @derive {Inspect, except: [:resource]}
  defstruct [:resource]

  @doc """
  Create a new queue
  """
  def new(), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Add a list of terms to the end of the queue atomically.
  Terms are added in order.

  You should almost always prefer using this function over `push_back/2`.

  You should especially prefer using this function over `push_back/2` if you
  are adding many items to the queue, as it is optimized
  for this specific use case, and is often ~10x faster than `push_back/2`.

  This function acquires a lock 1 time, regardless of how many items you add.
  `push_back/2` acquires a lock to add only a single item, so calling it in
  a hot loop results in many repeated lock acquisitions.
  """
  def extend(queue, list) when is_list(list) do
    extend_impl(queue, list)
  end

  @doc """
  Remove up to the first `n` items from the queue, or an empty list
  if the queue is empty.

  Returns less than `n` items if `len(queue)` < `n`.
  """
  def take(queue, n) when is_integer(n) and n >= 0 do
    take_impl(queue, n)
  end

  @doc """
  Add a single term to the end of the queue.

  This function is convenient for adding a single item,
  but you should almost always prefer using `extend/2`,
  as it is ~10x faster if you are adding multiple items.

  This function acquires a lock to add a single item,
  whereas `extend/2` acquires a lock a single time to add
  an arbitrary number of items, resulting in much less lock contention.
  """
  def push_back(_queue, _term), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Remove the first item from the head of the queue, or `nil`
  if the queue is empty.
  """
  def pop_front(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the contents of the queue as a list.
  """
  def to_list(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the length of the queue.
  """
  def count(_queue), do: :erlang.nif_error(:nif_not_loaded)

  defp extend_impl(_queue, _list_of_terms), do: :erlang.nif_error(:nif_not_loaded)

  defp take_impl(_queue, _n), do: :erlang.nif_error(:nif_not_loaded)
end

# TODO these impls can be sped up to use native functions
# TODO the native functions necessary don't exist yet
defimpl Enumerable, for: Queue do
  def count(queue) do
    {:ok, Queue.count(queue)}
  end

  def member?(_queue, _term) do
    {:error, __MODULE__}
  end

  def slice(queue) do
    {:ok, Queue.count(queue), fn queue -> Queue.to_list(queue) end}
  end

  def reduce(queue, acc, fun) do
    queue
    |> Queue.to_list()
    |> Enumerable.List.reduce(acc, fun)
  end
end
