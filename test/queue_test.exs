defmodule QueueTest do
  use ExUnit.Case
  doctest Queue

  describe "to_list/1" do
    test "empty queue is an empty list" do
      assert [] == Queue.to_list(Queue.new())
    end

    test "returns elements in insertion order" do
      q = Queue.new()

      Queue.push_back(q, "a")
      Queue.push_back(q, "b")
      Queue.push_back(q, "c")

      assert ["a", "b", "c"] == Queue.to_list(q)
    end

    test "preserves arbitrary terms" do
      terms = [nil, :atom, 1, -1.5, "binary", ~c"charlist", {1, :two}, [1, 2, 3], %{a: 1}, self()]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Queue.to_list(q)
    end

    test "is non-destructive" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert [1, 2, 3] == Queue.to_list(q)
      assert [1, 2, 3] == Queue.to_list(q)
      assert 3 == Queue.count(q)
      assert 1 == Queue.pop_front(q)
    end

    test "reflects elements already popped" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3, 4, 5])

      assert 1 == Queue.pop_front(q)
      assert [2, 3, 4, 5] == Queue.to_list(q)

      assert [2, 3] == Queue.take_front(q, 2)
      assert [4, 5] == Queue.to_list(q)
    end

    test "is empty again after the queue is drained" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert [1, 2, 3] == Queue.take_front(q, 3)
      assert [] == Queue.to_list(q)
    end

    test "sees elements pushed after a to_list call" do
      q = Queue.new()

      Queue.push_back(q, :a)
      assert [:a] == Queue.to_list(q)

      Queue.push_back(q, :b)
      assert [:a, :b] == Queue.to_list(q)
    end

    test "spans slab boundaries" do
      # SLAB_SIZE on the Rust side is 2^12, so this covers several slabs
      # plus a partially filled one.
      expected = Enum.to_list(1..(3 * 4096 + 7))

      q = Queue.new()
      Queue.extend_back(q, expected)

      assert expected == Queue.to_list(q)
      assert length(expected) == Queue.count(q)
    end

    test "spans slab boundaries after a partial pop" do
      expected = Enum.to_list(1..(2 * 4096))

      q = Queue.new()
      Queue.extend_back(q, expected)

      popped = 4096 + 100
      assert Enum.take(expected, popped) == Queue.take_front(q, popped)

      remaining = Enum.drop(expected, popped)
      assert remaining == Queue.to_list(q)
      assert length(remaining) == Queue.count(q)
    end

    test "agrees with len/1 as the queue is consumed" do
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..100))

      Enum.each(1..10, fn _ ->
        Queue.take_front(q, 7)
        assert Queue.count(q) == length(Queue.to_list(q))
      end)
    end
  end

  describe "count/1" do
    test "a new queue is empty" do
      assert 0 == Queue.count(Queue.new())
    end

    test "counts single pushes" do
      q = Queue.new()

      assert 0 == Queue.count(q)

      Queue.push_back(q, :a)
      assert 1 == Queue.count(q)

      Queue.push_back(q, :b)
      assert 2 == Queue.count(q)
    end

    test "counts bulk pushes" do
      q = Queue.new()

      Queue.extend_back(q, [1, 2, 3])
      assert 3 == Queue.count(q)

      Queue.extend_back(q, [4, 5])
      assert 5 == Queue.count(q)
    end

    test "pushing an empty list does not change the length" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2])

      Queue.extend_back(q, [])
      assert 2 == Queue.count(q)
    end

    test "is not affected by reading the queue" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      Queue.to_list(q)
      Queue.to_list(q)

      assert 3 == Queue.count(q)
    end

    test "decreases as elements are popped" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3, 4, 5])

      Queue.pop_front(q)
      assert 4 == Queue.count(q)

      Queue.take_front(q, 2)
      assert 2 == Queue.count(q)
    end

    test "is zero once the queue is drained" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      Queue.take_front(q, 3)
      assert 0 == Queue.count(q)
    end

    test "does not go negative when over-popping" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert [1, 2, 3] == Queue.take_front(q, 1000)
      assert 0 == Queue.count(q)

      assert nil == Queue.pop_front(q)
      assert 0 == Queue.count(q)
    end

    test "counts elements pushed after the queue was drained" do
      q = Queue.new()

      Queue.extend_back(q, [1, 2, 3])
      Queue.take_front(q, 3)
      assert 0 == Queue.count(q)

      Queue.extend_back(q, [4, 5])
      assert 2 == Queue.count(q)
      assert [4, 5] == Queue.to_list(q)
    end

    test "spans slab boundaries" do
      # SLAB_SIZE on the Rust side is 2^12, so this covers several slabs
      # plus a partially filled one.
      n = 3 * 4096 + 7

      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..n))

      assert n == Queue.count(q)

      popped = 4096 + 100
      Queue.take_front(q, popped)
      assert n - popped == Queue.count(q)
    end

    test "tracks length through interleaved pushes and pops" do
      q = Queue.new()

      Enum.reduce(1..50, 0, fn i, expected ->
        Queue.extend_back(q, Enum.to_list(1..i))
        popped = length(Queue.take_front(q, div(i, 2)))

        expected = expected + i - popped
        assert expected == Queue.count(q)
        expected
      end)
    end
  end

  describe "push_back/2" do
    test "returns the same queue it was given" do
      q = Queue.new()

      assert q == Queue.push_back(q, :a)
    end

    test "mutates in place, so the return value and the original alias" do
      q = Queue.new()
      q2 = Queue.push_back(q, :a)

      Queue.push_back(q2, :b)

      assert [:a, :b] == Queue.to_list(q)
      assert 2 == Queue.count(q)
    end

    test "can be piped" do
      q =
        Queue.new()
        |> Queue.push_back(1)
        |> Queue.push_back(2)
        |> Queue.push_back(3)

      assert [1, 2, 3] == Queue.to_list(q)
    end

    test "appends to the back" do
      q = Queue.new()

      Queue.push_back(q, :first)
      Queue.push_back(q, :second)

      assert :first == Queue.pop_front(q)
      assert :second == Queue.pop_front(q)
    end

    test "preserves arbitrary terms" do
      terms = [nil, :atom, 1, -1.5, "binary", ~c"charlist", {1, :two}, [1, 2, 3], %{a: 1}, self()]

      q = Queue.new()
      Enum.each(terms, &Queue.push_back(q, &1))

      assert terms == Queue.to_list(q)
    end

    test "preserves large and deeply nested terms" do
      terms = [
        :binary.copy("x", 1_000_000),
        Enum.reduce(1..1000, :leaf, fn i, acc -> {i, acc} end),
        Map.new(1..1000, fn i -> {i, Integer.to_string(i)} end)
      ]

      q = Queue.new()
      Enum.each(terms, &Queue.push_back(q, &1))

      assert terms == Queue.to_list(q)
    end

    test "keeps its own copy after the pushing process dies" do
      q = Queue.new()
      parent = self()

      pid =
        spawn(fn ->
          Queue.push_back(q, {:from_child, :binary.copy("y", 100_000)})
          send(parent, :pushed)
        end)

      ref = Process.monitor(pid)
      assert_receive :pushed
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      :erlang.garbage_collect()

      assert [{:from_child, :binary.copy("y", 100_000)}] == Queue.to_list(q)
    end

    test "duplicate terms are kept as separate elements" do
      q = Queue.new()

      Enum.each(1..3, fn _ -> Queue.push_back(q, :dup) end)

      assert [:dup, :dup, :dup] == Queue.to_list(q)
      assert 3 == Queue.count(q)
    end

    test "spans many slabs" do
      expected = Enum.to_list(1..(3 * 4096 + 7))

      q = Queue.new()
      Enum.each(expected, &Queue.push_back(q, &1))

      assert expected == Queue.to_list(q)
      assert length(expected) == Queue.count(q)
    end

    test "works on a queue that was drained" do
      q = Queue.new()

      Queue.push_back(q, :a)
      assert :a == Queue.pop_front(q)
      assert 0 == Queue.count(q)

      Queue.push_back(q, :b)
      assert [:b] == Queue.to_list(q)
      assert :b == Queue.pop_front(q)
    end

    test "interleaves correctly with extend_back/2" do
      q = Queue.new()

      Queue.push_back(q, 1)
      Queue.extend_back(q, [2, 3])
      Queue.push_back(q, 4)

      assert [1, 2, 3, 4] == Queue.to_list(q)
    end

    test "keeps every element when pushed concurrently from many processes" do
      q = Queue.new()
      per_process = 500

      tasks =
        for p <- 1..10 do
          Task.async(fn ->
            for i <- 1..per_process do
              Queue.push_back(q, {p, i})
            end
          end)
        end

      Enum.each(tasks, &Task.await(&1, 30_000))

      list = Queue.to_list(q)

      assert 10 * per_process == Queue.count(q)
      assert 10 * per_process == length(list)

      # Interleaving across processes is arbitrary, but each process's own
      # pushes must stay in order relative to each other.
      by_process = Enum.group_by(list, &elem(&1, 0), &elem(&1, 1))

      for p <- 1..10 do
        assert Enum.to_list(1..per_process) == by_process[p]
      end
    end
  end

  describe "extend_back/2" do
    test "returns the same queue it was given" do
      q = Queue.new()

      assert q == Queue.extend_back(q, [:a])
    end

    test "mutates in place, so the return value and the original alias" do
      q = Queue.new()
      q2 = Queue.extend_back(q, [:a, :b])

      Queue.extend_back(q2, [:c])

      assert [:a, :b, :c] == Queue.to_list(q)
      assert 3 == Queue.count(q)
    end

    test "can be piped" do
      q =
        Queue.new()
        |> Queue.extend_back([1, 2])
        |> Queue.extend_back([3, 4])

      assert [1, 2, 3, 4] == Queue.to_list(q)
    end

    test "appends in list order, to the back" do
      q = Queue.new()

      Queue.extend_back(q, [:a, :b])
      Queue.extend_back(q, [:c, :d])

      assert [:a, :b, :c, :d] == Queue.to_list(q)
      assert :a == Queue.pop_front(q)
    end

    test "an empty list is a no-op" do
      q = Queue.new()

      Queue.extend_back(q, [])
      assert 0 == Queue.count(q)
      assert [] == Queue.to_list(q)

      Queue.extend_back(q, [:a])
      Queue.extend_back(q, [])
      assert [:a] == Queue.to_list(q)
    end

    test "a single-element list behaves like push_back/2" do
      q = Queue.new()

      Queue.extend_back(q, [:only])

      assert [:only] == Queue.to_list(q)
      assert 1 == Queue.count(q)
    end

    test "preserves arbitrary terms" do
      terms = [nil, :atom, 1, -1.5, "binary", ~c"charlist", {1, :two}, [1, 2, 3], %{a: 1}, self()]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Queue.to_list(q)
    end

    test "preserves large and deeply nested terms" do
      terms = [
        :binary.copy("x", 1_000_000),
        Enum.reduce(1..1000, :leaf, fn i, acc -> {i, acc} end),
        Map.new(1..1000, fn i -> {i, Integer.to_string(i)} end)
      ]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Queue.to_list(q)
    end

    test "keeps duplicates as separate elements" do
      q = Queue.new()

      Queue.extend_back(q, [:dup, :dup, :dup])

      assert [:dup, :dup, :dup] == Queue.to_list(q)
      assert 3 == Queue.count(q)
    end

    test "keeps its own copy after the pushing process dies" do
      q = Queue.new()
      parent = self()
      expected = [{:from_child, :binary.copy("y", 100_000)}]

      pid =
        spawn(fn ->
          Queue.extend_back(q, [{:from_child, :binary.copy("y", 100_000)}])
          send(parent, :pushed)
        end)

      ref = Process.monitor(pid)
      assert_receive :pushed
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      :erlang.garbage_collect()

      assert expected == Queue.to_list(q)
    end

    test "fills a slab exactly, then rolls over" do
      # SLAB_SIZE on the Rust side is 2^12, so the first batch fills the
      # first slab exactly and the second starts a new one.
      q = Queue.new()

      Queue.extend_back(q, Enum.to_list(1..4096))
      assert 4096 == Queue.count(q)

      Queue.extend_back(q, [:overflow])
      assert 4097 == Queue.count(q)
      assert Enum.to_list(1..4096) ++ [:overflow] == Queue.to_list(q)
    end

    test "a single batch can span many slabs" do
      expected = Enum.to_list(1..(3 * 4096 + 7))

      q = Queue.new()
      Queue.extend_back(q, expected)

      assert expected == Queue.to_list(q)
      assert length(expected) == Queue.count(q)
    end

    test "works on a queue that was drained" do
      q = Queue.new()

      Queue.extend_back(q, [1, 2, 3])
      assert [1, 2, 3] == Queue.take_front(q, 3)
      assert 0 == Queue.count(q)

      Queue.extend_back(q, [4, 5])
      assert [4, 5] == Queue.to_list(q)
    end

    test "interleaves correctly with push_back/2" do
      q = Queue.new()

      Queue.extend_back(q, [1, 2])
      Queue.push_back(q, 3)
      Queue.extend_back(q, [4, 5])

      assert [1, 2, 3, 4, 5] == Queue.to_list(q)
    end

    test "rejects a non-list without touching the queue" do
      q = Queue.new()
      Queue.extend_back(q, [:a])

      # Passed through Enum.random/1 so the type checker doesn't flag the
      # deliberately-wrong literal at compile time.
      not_a_list = Enum.random([:not_a_list])
      assert_raise FunctionClauseError, fn -> Queue.extend_back(q, not_a_list) end

      assert [:a] == Queue.to_list(q)
      assert 1 == Queue.count(q)
    end

    # haven't found a great way to ensure you can't pass an improper list
    #
    # test "rejects an improper list without touching the queue" do
    #   q = Queue.new()
    #   Queue.extend_back(q, [:a])

    #   # NOTE: `is_list/1` is true for any cons cell, so rustler's list decoder
    #   # starts iterating and then panics part-way through instead of failing
    #   # the decode. That surfaces as `:nif_panicked` rather than the
    #   # ArgumentError a normal decode failure raises. See the non-list test
    #   # above for the well-behaved case.
    #   assert_raise ErlangError, fn -> Queue.extend_back(q, [:b | :c]) end

    #   assert [:a] == Queue.to_list(q)
    #   assert 1 == Queue.count(q)
    # end

    test "each concurrent batch lands contiguously" do
      # extend_back holds the queue lock for the whole batch, so batches
      # may interleave with each other but must never be split apart.
      q = Queue.new()
      batch_size = 500

      tasks =
        for p <- 1..10 do
          Task.async(fn ->
            Queue.extend_back(q, for(i <- 1..batch_size, do: {p, i}))
          end)
        end

      Enum.each(tasks, &Task.await(&1, 30_000))

      list = Queue.to_list(q)

      assert 10 * batch_size == Queue.count(q)
      assert 10 * batch_size == length(list)

      runs = Enum.chunk_by(list, &elem(&1, 0))

      assert 10 == length(runs)

      for run <- runs do
        [{p, _} | _] = run
        assert for(i <- 1..batch_size, do: {p, i}) == run
      end
    end
  end

  describe "pop_front/1" do
    test "an empty queue returns nil" do
      assert nil == Queue.pop_front(Queue.new())
    end

    test "an empty queue keeps returning nil" do
      q = Queue.new()

      assert nil == Queue.pop_front(q)
      assert nil == Queue.pop_front(q)
      assert 0 == Queue.count(q)
    end

    test "returns elements in insertion order" do
      q = Queue.new()
      Queue.extend_back(q, [:a, :b, :c])

      assert :a == Queue.pop_front(q)
      assert :b == Queue.pop_front(q)
      assert :c == Queue.pop_front(q)
      assert nil == Queue.pop_front(q)
    end

    test "removes the element it returns" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert 1 == Queue.pop_front(q)
      assert [2, 3] == Queue.to_list(q)
      assert 2 == Queue.count(q)
    end

    test "a popped nil is indistinguishable from an empty queue" do
      # `nil` is a legal element, so the return value alone can't tell you
      # whether the queue had anything in it. len/1 can.
      q = Queue.new()
      Queue.push_back(q, nil)

      assert 1 == Queue.count(q)
      assert nil == Queue.pop_front(q)
      assert 0 == Queue.count(q)
    end

    test "preserves arbitrary terms" do
      terms = [nil, :atom, 1, -1.5, "binary", ~c"charlist", {1, :two}, [1, 2, 3], %{a: 1}, self()]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Enum.map(terms, fn _ -> Queue.pop_front(q) end)
    end

    test "preserves large and deeply nested terms" do
      terms = [
        :binary.copy("x", 1_000_000),
        Enum.reduce(1..1000, :leaf, fn i, acc -> {i, acc} end),
        Map.new(1..1000, fn i -> {i, Integer.to_string(i)} end)
      ]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Enum.map(terms, fn _ -> Queue.pop_front(q) end)
    end

    test "drains a queue that spans many slabs, in order" do
      # SLAB_SIZE on the Rust side is 2^12, so this walks the front position
      # across several slab boundaries one element at a time.
      n = 2 * 4096 + 7
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..n))

      Enum.each(1..n, fn i ->
        assert i == Queue.pop_front(q)
        assert n - i == Queue.count(q)
      end)

      assert nil == Queue.pop_front(q)
      assert [] == Queue.to_list(q)
    end

    test "works again after the queue was drained" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2])

      assert 1 == Queue.pop_front(q)
      assert 2 == Queue.pop_front(q)
      assert nil == Queue.pop_front(q)

      Queue.push_back(q, 3)
      assert 3 == Queue.pop_front(q)
    end

    test "interleaves correctly with take_front/2" do
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..6))

      assert 1 == Queue.pop_front(q)
      assert [2, 3] == Queue.take_front(q, 2)
      assert 4 == Queue.pop_front(q)
      assert [5, 6] == Queue.take_front(q, 10)
      assert nil == Queue.pop_front(q)
    end

    test "sees elements pushed between pops" do
      q = Queue.new()

      Queue.push_back(q, :a)
      assert :a == Queue.pop_front(q)
      assert nil == Queue.pop_front(q)

      Queue.push_back(q, :b)
      Queue.push_back(q, :c)
      assert :b == Queue.pop_front(q)

      Queue.push_back(q, :d)
      assert :c == Queue.pop_front(q)
      assert :d == Queue.pop_front(q)
    end

    test "hands each element to exactly one concurrent popper" do
      n = 5_000
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..n))

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Stream.repeatedly(fn -> Queue.pop_front(q) end)
            |> Enum.take_while(&(&1 != nil))
          end)
        end

      popped = tasks |> Enum.flat_map(&Task.await(&1, 30_000))

      assert Enum.to_list(1..n) == Enum.sort(popped)
      assert 0 == Queue.count(q)
    end
  end

  describe "take_front/2" do
    test "an empty queue returns an empty list" do
      assert [] == Queue.take_front(Queue.new(), 5)
    end

    test "returns elements in order and removes them" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3, 4, 5])

      assert [1, 2, 3] == Queue.take_front(q, 3)
      assert [4, 5] == Queue.to_list(q)
      assert 2 == Queue.count(q)
    end

    test "asking for zero elements is a no-op" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert [] == Queue.take_front(q, 0)
      assert [1, 2, 3] == Queue.to_list(q)
      assert 3 == Queue.count(q)
    end

    test "asking for one element behaves like pop_front/1" do
      q = Queue.new()
      Queue.extend_back(q, [:a, :b])

      assert [:a] == Queue.take_front(q, 1)
      assert :b == Queue.pop_front(q)
    end

    test "asking for more than is available returns what there is" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert [1, 2, 3] == Queue.take_front(q, 1000)
      assert [] == Queue.to_list(q)
      assert 0 == Queue.count(q)

      assert [] == Queue.take_front(q, 1000)
    end

    test "preserves arbitrary terms" do
      terms = [nil, :atom, 1, -1.5, "binary", ~c"charlist", {1, :two}, [1, 2, 3], %{a: 1}, self()]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Queue.take_front(q, length(terms))
    end

    test "preserves large and deeply nested terms" do
      terms = [
        :binary.copy("x", 1_000_000),
        Enum.reduce(1..1000, :leaf, fn i, acc -> {i, acc} end),
        Map.new(1..1000, fn i -> {i, Integer.to_string(i)} end)
      ]

      q = Queue.new()
      Queue.extend_back(q, terms)

      assert terms == Queue.take_front(q, 3)
    end

    test "a single call can span many slabs" do
      # SLAB_SIZE on the Rust side is 2^12, so one call has to walk across
      # several exhausted slabs plus a partially filled one.
      expected = Enum.to_list(1..(3 * 4096 + 7))

      q = Queue.new()
      Queue.extend_back(q, expected)

      assert expected == Queue.take_front(q, length(expected))
      assert 0 == Queue.count(q)
      assert [] == Queue.to_list(q)
    end

    test "repeated partial pops drain a multi-slab queue in order" do
      n = 3 * 4096
      chunk = 1000

      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..n))

      drained =
        Stream.repeatedly(fn -> Queue.take_front(q, chunk) end)
        |> Enum.take_while(&(&1 != []))
        |> List.flatten()

      assert Enum.to_list(1..n) == drained
      assert 0 == Queue.count(q)
    end

    test "a pop that lands exactly on a slab boundary leaves the rest intact" do
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..(4096 + 5)))

      assert Enum.to_list(1..4096) == Queue.take_front(q, 4096)
      assert 5 == Queue.count(q)
      assert Enum.to_list(4097..4101) == Queue.to_list(q)
      assert Enum.to_list(4097..4101) == Queue.take_front(q, 5)
    end

    test "works again after the queue was drained" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert [1, 2, 3] == Queue.take_front(q, 3)
      assert [] == Queue.take_front(q, 3)

      Queue.extend_back(q, [4, 5])
      assert [4, 5] == Queue.take_front(q, 3)
    end

    test "sees elements pushed between pops" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2])

      assert [1] == Queue.take_front(q, 1)

      Queue.extend_back(q, [3, 4])
      assert [2, 3] == Queue.take_front(q, 2)

      Queue.push_back(q, 5)
      assert [4, 5] == Queue.take_front(q, 5)
    end

    test "rejects a negative count without touching the queue" do
      q = Queue.new()
      Queue.extend_back(q, [:a])

      # Passed through Enum.random/1 so the type checker doesn't flag the
      # deliberately-wrong literal at compile time.
      negative = Enum.random([-1])
      assert_raise FunctionClauseError, fn -> Queue.take_front(q, negative) end

      assert [:a] == Queue.to_list(q)
      assert 1 == Queue.count(q)
    end

    test "rejects a non-integer count without touching the queue" do
      q = Queue.new()
      Queue.extend_back(q, [:a])

      not_an_integer = Enum.random([:two])
      assert_raise FunctionClauseError, fn -> Queue.take_front(q, not_an_integer) end

      assert [:a] == Queue.to_list(q)
      assert 1 == Queue.count(q)
    end

    test "each concurrent batch is a contiguous run" do
      # take_front holds the queue lock for the whole batch, so concurrent
      # callers may interleave with each other but no batch may be split.
      n = 5_000
      chunk = 100

      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..n))

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Stream.repeatedly(fn -> Queue.take_front(q, chunk) end)
            |> Enum.take_while(&(&1 != []))
          end)
        end

      batches = Enum.flat_map(tasks, &Task.await(&1, 30_000))

      for batch <- batches do
        [first | _] = batch
        assert Enum.to_list(first..(first + length(batch) - 1)) == batch
      end

      assert Enum.to_list(1..n) == batches |> List.flatten() |> Enum.sort()
      assert 0 == Queue.count(q)
    end
  end

  describe "Enumerable" do
    test "a new queue counts zero" do
      assert {:ok, 0} == Enumerable.count(Queue.new())
    end

    test "returns {:ok, count}, not a bare integer" do
      # The protocol requires {:ok, count} | {:error, module}; anything else
      # blows up inside Enum.count/1.
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert {:ok, 3} == Enumerable.count(q)
    end

    test "agrees with Queue.count/1" do
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..10))

      assert {:ok, Queue.count(q)} == Enumerable.count(q)
    end

    test "Enum.count/1 goes through the protocol" do
      q = Queue.new()
      Queue.extend_back(q, [:a, :b, :c])

      assert 3 == Enum.count(q)
    end

    test "counting does not consume the queue" do
      q = Queue.new()
      Queue.extend_back(q, [1, 2, 3])

      assert 3 == Enum.count(q)
      assert 3 == Enum.count(q)
      assert [1, 2, 3] == Queue.to_list(q)
    end

    test "tracks pushes and pops" do
      q = Queue.new()
      assert 0 == Enum.count(q)

      Queue.push_back(q, :a)
      assert 1 == Enum.count(q)

      Queue.extend_back(q, [:b, :c])
      assert 3 == Enum.count(q)

      Queue.pop_front(q)
      assert 2 == Enum.count(q)

      Queue.take_front(q, 2)
      assert 0 == Enum.count(q)
    end

    test "counts a queue that spans many slabs" do
      # SLAB_SIZE on the Rust side is 2^12, so this covers several slabs
      # plus a partially filled one.
      n = 3 * 4096 + 7

      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..n))

      assert {:ok, n} == Enumerable.count(q)

      popped = 4096 + 100
      Queue.take_front(q, popped)

      assert {:ok, n - popped} == Enumerable.count(q)
    end

    test "nil elements are counted like any other term" do
      q = Queue.new()
      Queue.extend_back(q, [nil, nil, nil])

      assert 3 == Enum.count(q)
    end

    test "Enum.empty?/1 uses the count" do
      q = Queue.new()
      assert Enum.empty?(q)

      Queue.push_back(q, :a)
      refute Enum.empty?(q)

      Queue.pop_front(q)
      assert Enum.empty?(q)
    end

    test "agrees with the length of the enumerated contents" do
      q = Queue.new()
      Queue.extend_back(q, Enum.to_list(1..100))

      Enum.each(1..10, fn _ ->
        Queue.take_front(q, 7)
        assert Enum.count(q) == length(Enum.to_list(q))
      end)
    end

    test "Enum.at/3 indexes from the front of the queue" do
      q = Queue.new()
      Queue.extend_back(q, [:a, :b, :c])

      assert :a == Enum.at(q, 0)
      assert :b == Enum.at(q, 1)
      assert :c == Enum.at(q, 2)

      # Negative indexes count back from the end.
      assert :c == Enum.at(q, -1)
      assert :a == Enum.at(q, -3)

      # Out of range on either side falls back to the default.
      assert nil == Enum.at(q, 3)
      assert nil == Enum.at(q, -4)
      assert :missing == Enum.at(q, 3, :missing)
      assert :missing == Enum.at(Queue.new(), 0, :missing)

      # Indexing does not consume the queue.
      assert [:a, :b, :c] == Queue.to_list(q)
      assert 3 == Queue.count(q)
    end
  end
end
