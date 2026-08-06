# Run with: MIX_ENV=test mix run benchmarks.exs

inputs = %{
  "1_000" => Enum.to_list(1..100),
  "10_000" => Enum.to_list(1..10_000),
  "100_000" => Enum.to_list(1..100_000),
  "1_000_000" => Enum.to_list(1..1_000_000)
}

defmodule ErlangQueueServer do
  use GenServer

  def start_link(list \\ []) do
    GenServer.start_link(__MODULE__, list)
  end

  def init(list) do
    {:ok, :queue.from_list(list)}
  end

  def set(server, list \\ []) do
    GenServer.call(server, {:set, list})
  end

  def in_async(server, el) do
    GenServer.cast(server, {:in, el})
  end

  def in_sync(server, el) do
    GenServer.call(server, {:in, el})
  end

  def out(server) do
    GenServer.call(server, :out)
  end

  def pop_front_n(server, n) do
    GenServer.call(server, {:pop_front_n, n})
  end

  def handle_cast({:in, el}, q) do
    {:noreply, :queue.in(el, q)}
  end

  def handle_call({:set, list}, _from, _q) do
    {:reply, :ok, :queue.from_list(list)}
  end

  def handle_call({:in, el}, _from, q) do
    {:reply, :ok, :queue.in(el, q)}
  end

  def handle_call(:out, _from, q) do
    case :queue.out(q) do
      {{:value, v}, q2} ->
        {:reply, v, q2}

      {:empty, q2} ->
        {:reply, nil, q2}
    end
  end

  def handle_call({:pop_front_n, n}, _from, q) do
    {q2, q3} = :queue.split(n, q)
    {:reply, q2, q3}
  end
end

{:ok, erl_q_server} = ErlangQueueServer.start_link()

Benchee.run(
  %{
    ":queue.out/1" => fn {_q, erl_q, n} ->
      Enum.reduce(1..n, erl_q, fn _, _acc ->
        ErlangQueueServer.out(erl_q_server)
      end)
    end,
    ":queue.split/2" => fn {_q, _erl_q, n} ->
      ErlangQueueServer.pop_front_n(erl_q_server, n)
    end,
    "Queue.pop_front/1" => fn {q, _erl_q, n} ->
      Enum.each(1..n, fn _ ->
        Queue.pop_front(q)
      end)
    end,
    "Queue.pop_front_n/2" => fn {q, _erl_q, n} ->
      Queue.pop_front_n(q, n)
    end
  },
  warmup: 2,
  time: 5,
  before_each: fn input ->
    {
      Queue.new() |> Queue.push_back_n(input),
      ErlangQueueServer.set(erl_q_server, input),
      trunc(Enum.count(input) / 2)
    }
  end,
  inputs: inputs,
  print: [fast_warning: false]
)

Benchee.run(
  %{
    "Queue.push_back/2" => fn {q, _, input} ->
      Enum.each(input, fn i -> Queue.push_back(q, i) end)
    end,
    "Queue.push_back_n/2" => fn {q, _, input} -> Queue.push_back_n(q, input) end,
    ":queue.in/2 - async" => fn {_q, _, input} ->
      Enum.each(input, fn i ->
        ErlangQueueServer.in_async(erl_q_server, i)
      end)
    end,
    ":queue.in/2 - sync" => fn {_q, _, input} ->
      Enum.each(input, fn i ->
        ErlangQueueServer.in_sync(erl_q_server, i)
      end)
    end
  },
  warmup: 2,
  time: 3,
  before_each: fn input ->
    {
      Queue.new(),
      ErlangQueueServer.set(erl_q_server, []),
      input
    }
  end,
  inputs: inputs,
  print: [fast_warning: false]
)
