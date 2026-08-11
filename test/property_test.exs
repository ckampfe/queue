defmodule MockParityTest do
  use ExUnit.Case, async: true

  # Runs the same op sequence against the real NIF queue and the mock,
  # asserting every reply and the resulting contents agree.

  setup do
    pid = Queue.MockQueue.new()
    {:ok, real_queue: Queue.new(), mock_queue: pid}
  end

  defp assert_both(%{real_queue: real_queue, mock_queue: mock_queue}, fun, args) do
    real_result = apply(Queue, fun, [real_queue | args])
    mock_result = apply(Queue.MockQueue, fun, [mock_queue | args])

    # mutators return the queue handle itself; compare only value replies
    real_result = if real_result == real_queue, do: :queue_handle, else: real_result
    mock_result = if mock_result == mock_queue, do: :queue_handle, else: mock_result

    assert real_result == mock_result,
           "#{fun}(#{inspect(args)}): real #{inspect(real_result)} != mock #{inspect(mock_result)}"

    assert Queue.to_list(real_queue) == Queue.MockQueue.to_list(mock_queue),
           "contents diverged after #{fun}"

    assert Queue.count(real_queue) == Queue.MockQueue.count(mock_queue),
           "count diverged after #{fun}"

    real_result
  end

  test "parity under randomized ops", ctx do
    ops = [
      {:extend_back, fn -> [Enum.take_random(1..4000, :rand.uniform(6) - 1)] end},
      {:extend_front, fn -> [Enum.take_random(1..4000, :rand.uniform(6) - 1)] end},
      {:push_back, fn -> [:rand.uniform(50)] end},
      {:push_front, fn -> [:rand.uniform(50)] end},
      {:take_front, fn -> [:rand.uniform(2000) - 1] end},
      {:take_back, fn -> [:rand.uniform(2000) - 1] end},
      {:pop_front, fn -> [] end},
      {:pop_back, fn -> [] end},
      {:peek_front, fn -> [] end},
      {:peek_back, fn -> [] end},
      {:count, fn -> [] end},
      {:to_list, fn -> [] end}
    ]

    for _ <- 1..300_000 do
      {fun, gen} = Enum.random(ops)
      assert_both(ctx, fun, gen.())
    end
  end
end
