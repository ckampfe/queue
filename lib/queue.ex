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

  ## Examples

      iex> q = Queue.new()
      iex> Queue.count(q)
      0
      iex> Queue.to_list(q)
      []

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

  ## Examples

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [:a, :b])
      iex> Queue.extend_back(q, [:c])
      iex> Queue.to_list(q)
      [:a, :b, :c]

  An empty list leaves the queue alone:

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [:a])
      iex> Queue.extend_back(q, [])
      iex> Queue.to_list(q)
      [:a]

  """
  def extend_back(queue, list) when is_list(list) do
    extend_back_impl(queue, list)
  end

  @doc """
  Add a list of terms to the front of the queue atomically.

  Each term is prepended in the order it appears in the list, so the batch
  lands in the queue reversed: the last term of the list ends up at the very
  front.

  You should almost always prefer using this function over `push_front/2`.

  You should especially prefer using this function over `push_front/2` if you
  are adding many items to the queue, as it is optimized
  for this specific use case, and is often ~10x faster than `push_front/2`.

  This function acquires a lock 1 time, regardless of how many items you add.
  `push_front/2` acquires a lock to add only a single item, so calling it in
  a hot loop results in many repeated lock acquisitions.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [:a, :b, :c])
      iex> Queue.extend_front(q, [1, 2, 3])
      iex> Queue.to_list(q)
      [3, 2, 1, :a, :b, :c]

  Each batch lands in front of the one before it:

      iex> q = Queue.new()
      iex> Queue.extend_front(q, [:a, :b])
      iex> Queue.extend_front(q, [:c, :d])
      iex> Queue.to_list(q)
      [:d, :c, :b, :a]

  """
  def extend_front(queue, list) when is_list(list) do
    extend_front_impl(queue, list)
  end

  @doc """
  Remove up to `n` items from the front of the queue, or an empty list
  if the queue is empty.

  Returns less than `n` items if `len(queue)` < `n`.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [1, 2, 3, 4])
      iex> Queue.take_front(q, 2)
      [1, 2]
      iex> Queue.take_front(q, 100)
      [3, 4]
      iex> Queue.take_front(q, 1)
      []

  """
  def take_front(queue, n) when is_integer(n) and n >= 0 do
    if n <= 1024 do
      take_front_small(queue, n)
    else
      take_front_large(queue, n)
    end
  end

  @doc """
  Remove up to `n` items from the back of the queue, or an empty list
  if the queue is empty.

  Items come out back to front, as if `pop_back/1` had been called `n` times,
  so a batch taken off one queue's back can be moved to another queue's front
  with `extend_front/2` without reordering it.

  Returns less than `n` items if `len(queue)` < `n`.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [1, 2, 3, 4])
      iex> Queue.take_back(q, 2)
      [4, 3]
      iex> Queue.to_list(q)
      [1, 2]
      iex> Queue.take_back(q, 100)
      [2, 1]
      iex> Queue.take_back(q, 1)
      []

  Moving items from the back of one queue to the front of another keeps their
  order:

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [1, 2, 3, 4])
      iex> other = Queue.new()
      iex> Queue.extend_front(other, Queue.take_back(q, 2))
      iex> Queue.to_list(other)
      [3, 4]

  """
  def take_back(queue, n) when is_integer(n) and n >= 0 do
    if n <= 1024 do
      take_back_small(queue, n)
    else
      take_back_large(queue, n)
    end
  end

  @doc """
  Add a single term to the end of the queue.

  This function is convenient for adding a single item,
  but you should almost always prefer using `extend_back/2`,
  as it is ~10x faster if you are adding multiple items.

  This function acquires a lock to add a single item,
  whereas `extend_back/2` acquires a lock a single time to add
  an arbitrary number of items, resulting in much less lock contention.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.push_back(q, :a)
      iex> Queue.push_back(q, :b)
      iex> Queue.to_list(q)
      [:a, :b]

  """
  def push_back(_queue, _term), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Add a single term to the front of the queue.

  This function is convenient for adding a single item,
  but you should almost always prefer using `extend_front/2`,
  as it is ~10x faster if you are adding multiple items.

  This function acquires a lock to add a single item,
  whereas `extend_front/2` acquires a lock a single time to add
  an arbitrary number of items, resulting in much less lock contention.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.push_front(q, :b)
      iex> Queue.push_front(q, :a)
      iex> Queue.to_list(q)
      [:a, :b]

  """
  def push_front(_queue, _term), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Remove the first item from the head of the queue, or `nil`
  if the queue is empty.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [:a, :b])
      iex> Queue.pop_front(q)
      :a
      iex> Queue.pop_front(q)
      :b
      iex> Queue.pop_front(q)
      nil

  `nil` is a legal element, so the return value alone cannot tell you whether
  the queue was empty. `count/1` can:

      iex> q = Queue.new()
      iex> Queue.push_back(q, nil)
      iex> Queue.count(q)
      1
      iex> Queue.pop_front(q)
      nil
      iex> Queue.count(q)
      0

  """
  def pop_front(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Remove the last item from the tail of the queue, or `nil`
  if the queue is empty.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.extend_back(q, [:a, :b])
      iex> Queue.pop_back(q)
      :b
      iex> Queue.pop_back(q)
      :a
      iex> Queue.pop_back(q)
      nil

  `nil` is a legal element, so the return value alone cannot tell you whether
  the queue was empty. `count/1` can:

      iex> q = Queue.new()
      iex> Queue.push_back(q, nil)
      iex> Queue.count(q)
      1
      iex> Queue.pop_back(q)
      nil
      iex> Queue.count(q)
      0

  """
  def pop_back(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  View the item at the front of the queue if the queue is not empty,
  `nil` if it is.

  Does not modify the queue.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.peek_front(q)
      nil
      iex> Queue.extend_back(q, [:a, :b])
      iex> Queue.peek_front(q)
      :a
      iex> Queue.count(q)
      2

  """
  def peek_front(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  View the item at the back of the queue if the queue is not empty,
  `nil` if it is.

  Does not modify the queue.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.peek_back(q)
      nil
      iex> Queue.extend_back(q, [:a, :b])
      iex> Queue.peek_back(q)
      :b
      iex> Queue.count(q)
      2

  """
  def peek_back(_queue), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Returns the contents of the queue as a list.
  Does not modify the queue.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.to_list(q)
      []
      iex> Queue.extend_back(q, [1, 2, 3])
      iex> Queue.to_list(q)
      [1, 2, 3]
      iex> Queue.to_list(q)
      [1, 2, 3]

  """
  def to_list(_queue), do: :erlang.nif_error(:nif_not_loaded)

  def from_list(list) when is_list(list) do
    from_list_impl(list)
  end

  @doc """
  Returns the length of the queue.
  Does not modify the queue.

  ## Examples

      iex> q = Queue.new()
      iex> Queue.count(q)
      0
      iex> Queue.extend_back(q, [:a, :b])
      iex> Queue.count(q)
      2
      iex> Queue.pop_front(q)
      iex> Queue.count(q)
      1

  """
  def count(_queue), do: :erlang.nif_error(:nif_not_loaded)

  def from_list_impl(_list), do: :erlang.nif_error(:nif_not_loaded)

  defp extend_back_impl(_queue, _list_of_terms), do: :erlang.nif_error(:nif_not_loaded)
  defp extend_front_impl(_queue, _list_of_terms), do: :erlang.nif_error(:nif_not_loaded)

  defp take_front_small(_queue, _n), do: :erlang.nif_error(:nif_not_loaded)
  defp take_front_large(_queue, _n), do: :erlang.nif_error(:nif_not_loaded)

  defp take_back_small(_queue, _n), do: :erlang.nif_error(:nif_not_loaded)
  defp take_back_large(_queue, _n), do: :erlang.nif_error(:nif_not_loaded)
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
