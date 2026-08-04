defmodule Queue do
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
  Add a single term to the end of the queue.
  """
  def push_back(_queue, _term), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Add a list of terms to the end of the queue.
  Terms are added in order, atomically.
  """
  def push_back_n(queue, list) when is_list(list) do
    push_back_n_impl(queue, list)
  end

  @doc """
  Remove the first item from the head of the queue, or `nil`
  if the queue is empty.
  """
  def pop_front(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Remove up to the first `n` items from the queue, or an empty list
  if the queue is empty.

  Returns less than `n` items if `len(queue)` < `n`.
  """
  def pop_front_n(queue, n) when is_integer(n) and n >= 0 do
    pop_front_n_impl(queue, n)
  end

  @doc """
  Returns the contents of the queue as a list.
  """
  def to_list(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the length of the queue.
  """
  def count(_queue), do: :erlang.nif_error(:nif_not_loaded)

  defp push_back_n_impl(_queue, list_of_terms) when is_list(list_of_terms),
    do: :erlang.nif_error(:nif_not_loaded)

  defp pop_front_n_impl(_queue, _n), do: :erlang.nif_error(:nif_not_loaded)
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
