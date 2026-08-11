defmodule Queue.OracleQueue do
  @moduledoc """
  A queue server that implements the same interface
  and behavior as the Queue NIF, so we can run property
  tests against them and assert that they return the same results.

  The internals differ significantly, but they should behave the same.
  """

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def new() do
    {:ok, pid} = GenServer.start_link(__MODULE__, nil)
    pid
  end

  def init(_) do
    {:ok, []}
  end

  def extend_back(queue, list) when is_list(list) do
    GenServer.call(queue, {:extend_back, list})
  end

  def extend_front(queue, list) when is_list(list) do
    GenServer.call(queue, {:extend_front, list})
  end

  def take_front(queue, n) when is_integer(n) and n >= 0 do
    GenServer.call(queue, {:take_front, n})
  end

  def take_back(queue, n) when is_integer(n) and n >= 0 do
    GenServer.call(queue, {:take_back, n})
  end

  def push_back(queue, term) do
    GenServer.call(queue, {:push_back, term})
  end

  def push_front(queue, term) do
    GenServer.call(queue, {:push_front, term})
  end

  def pop_front(queue) do
    GenServer.call(queue, :pop_front)
  end

  def pop_back(queue) do
    GenServer.call(queue, :pop_back)
  end

  def peek_front(queue) do
    GenServer.call(queue, :peek_front)
  end

  def peek_back(queue) do
    GenServer.call(queue, :peek_back)
  end

  def to_list(queue) do
    GenServer.call(queue, :to_list)
  end

  def count(queue) do
    GenServer.call(queue, :count)
  end

  def handle_call({:extend_back, list}, _from, contents) do
    {:reply, self(), contents ++ list}
  end

  def handle_call({:extend_front, list}, _from, contents) do
    {:reply, self(), Enum.reverse(list) ++ contents}
  end

  def handle_call({:take_front, n}, _from, contents) do
    {taken, rest} = Enum.split(contents, n)
    {:reply, taken, rest}
  end

  def handle_call({:take_back, n}, _from, contents) do
    {taken, rest} = contents |> Enum.reverse() |> Enum.split(n)
    {:reply, taken, Enum.reverse(rest)}
  end

  def handle_call({:push_back, term}, _from, contents) do
    {:reply, self(), contents ++ [term]}
  end

  def handle_call({:push_front, term}, _from, contents) do
    {:reply, self(), [term | contents]}
  end

  def handle_call(:pop_front, _from, contents) do
    case contents do
      [] -> {:reply, nil, []}
      [first | rest] -> {:reply, first, rest}
    end
  end

  def handle_call(:pop_back, _from, contents) do
    case Enum.reverse(contents) do
      [] -> {:reply, nil, []}
      [last | rest] -> {:reply, last, Enum.reverse(rest)}
    end
  end

  def handle_call(:peek_front, _from, contents) do
    {:reply, List.first(contents), contents}
  end

  def handle_call(:peek_back, _from, contents) do
    {:reply, List.last(contents), contents}
  end

  def handle_call(:to_list, _from, contents) do
    {:reply, contents, contents}
  end

  def handle_call(:count, _from, contents) do
    {:reply, length(contents), contents}
  end
end
