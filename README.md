# Queue

An Elixir NIF providing a shared, mutable, double-ended FIFO queue, optimized for bulk operations.


[![Elixir CI](https://github.com/ckampfe/queue/actions/workflows/elixir.yml/badge.svg)](https://github.com/ckampfe/queue/actions/workflows/elixir.yml)

```elixir
q = Queue.new()
Queue.extend_back(q, [1, 2, 3])
Queue.count(q)
#=> 3
Queue.pop_front(q)
#=> 1
Queue.take_front(q, 3)
#=> [2, 3]
Queue.take_front(q, 3)
#=> []
Queue.push_back(q, 99)
Queue.to_list(q)
#=> [99]
```


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `queue` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:queue, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/queue>.

## Benchmarks

```
Operating System: macOS
CPU Information: Apple M1 Max
Number of Available Cores: 10
Available memory: 64 GB
Elixir 1.20.2
Erlang 29.0.4
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: 100_000, 10_000, 1_000, 1_000_000
Estimated total run time: 1 min 52 s
Excluding outliers: false

Benchmarking :queue.out/1 with input 100_000 ...
Benchmarking :queue.out/1 with input 10_000 ...
Benchmarking :queue.out/1 with input 1_000 ...
Benchmarking :queue.out/1 with input 1_000_000 ...
Benchmarking :queue.split/2 with input 100_000 ...
Benchmarking :queue.split/2 with input 10_000 ...
Benchmarking :queue.split/2 with input 1_000 ...
Benchmarking :queue.split/2 with input 1_000_000 ...
Benchmarking Queue.pop_front/1 with input 100_000 ...
Benchmarking Queue.pop_front/1 with input 10_000 ...
Benchmarking Queue.pop_front/1 with input 1_000 ...
Benchmarking Queue.pop_front/1 with input 1_000_000 ...
Benchmarking Queue.take/2 with input 100_000 ...
Benchmarking Queue.take/2 with input 10_000 ...
Benchmarking Queue.take/2 with input 1_000 ...
Benchmarking Queue.take/2 with input 1_000_000 ...
Calculating statistics...
Formatting results...

##### With input 100_000 #####
Name                        ips        average  deviation         median         99th %
:queue.split/2           791.89        1.26 ms    ±83.67%        0.54 ms        2.93 ms
Queue.take/2             703.19        1.42 ms    ±46.88%        0.90 ms        3.01 ms
:queue.out/1              21.10       47.40 ms     ±1.04%       47.36 ms       49.80 ms
Queue.pop_front/1         16.25       61.53 ms     ±4.80%       60.72 ms       76.18 ms

Comparison: 
:queue.split/2           791.89
Queue.take/2             703.19 - 1.13x slower +0.159 ms
:queue.out/1              21.10 - 37.53x slower +46.14 ms
Queue.pop_front/1         16.25 - 48.72x slower +60.26 ms

##### With input 10_000 #####
Name                        ips        average  deviation         median         99th %
Queue.take/2             9.60 K       0.104 ms    ±58.53%      0.0925 ms        0.44 ms
:queue.split/2           7.88 K       0.127 ms   ±101.90%      0.0516 ms        0.39 ms
:queue.out/1             0.21 K        4.65 ms     ±1.41%        4.65 ms        4.90 ms
Queue.pop_front/1       0.162 K        6.16 ms    ±13.34%        5.97 ms       10.76 ms

Comparison: 
Queue.take/2             9.60 K
:queue.split/2           7.88 K - 1.22x slower +0.0228 ms
:queue.out/1             0.21 K - 44.67x slower +4.55 ms
Queue.pop_front/1       0.162 K - 59.17x slower +6.06 ms

##### With input 1_000 #####
Name                        ips        average  deviation         median         99th %
Queue.take/2           392.60 K        2.55 μs  ±1588.76%        1.92 μs        5.88 μs
:queue.split/2         243.73 K        4.10 μs  ±1720.85%        1.42 μs        2.63 μs
:queue.out/1            19.25 K       51.93 μs    ±25.32%       48.33 μs      103.67 μs
Queue.pop_front/1       15.96 K       62.64 μs    ±81.37%       58.58 μs       99.34 μs

Comparison: 
Queue.take/2           392.60 K
:queue.split/2         243.73 K - 1.61x slower +1.56 μs
:queue.out/1            19.25 K - 20.39x slower +49.39 μs
Queue.pop_front/1       15.96 K - 24.59x slower +60.09 μs

##### With input 1_000_000 #####
Name                        ips        average  deviation         median         99th %
Queue.take/2              72.79       13.74 ms    ±42.91%       10.12 ms       23.23 ms
:queue.split/2            68.69       14.56 ms    ±74.10%        7.30 ms       39.83 ms
:queue.out/1               2.11      473.73 ms     ±1.18%      474.21 ms      480.69 ms
Queue.pop_front/1          1.36      736.83 ms     ±8.56%      725.19 ms      854.34 ms

Comparison: 
Queue.take/2              72.79
:queue.split/2            68.69 - 1.06x slower +0.82 ms
:queue.out/1               2.11 - 34.48x slower +459.99 ms
Queue.pop_front/1          1.36 - 53.64x slower +723.09 ms
Operating System: macOS
CPU Information: Apple M1 Max
Number of Available Cores: 10
Available memory: 64 GB
Elixir 1.20.2
Erlang 29.0.4
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 3 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: 100_000, 10_000, 1_000, 1_000_000
Estimated total run time: 1 min 20 s
Excluding outliers: false

Benchmarking :queue.in/2 - async with input 100_000 ...
Benchmarking :queue.in/2 - async with input 10_000 ...
Benchmarking :queue.in/2 - async with input 1_000 ...
Benchmarking :queue.in/2 - async with input 1_000_000 ...
Benchmarking :queue.in/2 - sync with input 100_000 ...
Benchmarking :queue.in/2 - sync with input 10_000 ...
Benchmarking :queue.in/2 - sync with input 1_000 ...
Benchmarking :queue.in/2 - sync with input 1_000_000 ...
Benchmarking Queue.extend/2 with input 100_000 ...
Benchmarking Queue.extend/2 with input 10_000 ...
Benchmarking Queue.extend/2 with input 1_000 ...
Benchmarking Queue.extend/2 with input 1_000_000 ...
Benchmarking Queue.push_back/2 with input 100_000 ...
Benchmarking Queue.push_back/2 with input 10_000 ...
Benchmarking Queue.push_back/2 with input 1_000 ...
Benchmarking Queue.push_back/2 with input 1_000_000 ...
Calculating statistics...
Formatting results...

##### With input 100_000 #####
Name                          ips        average  deviation         median         99th %
Queue.extend/2             824.21        1.21 ms    ±12.66%        1.19 ms        1.77 ms
Queue.push_back/2           84.92       11.78 ms     ±0.84%       11.76 ms       12.05 ms
:queue.in/2 - async         66.85       14.96 ms     ±3.70%       14.94 ms       16.73 ms
:queue.in/2 - sync          10.84       92.29 ms     ±0.91%       91.96 ms       95.45 ms

Comparison: 
Queue.extend/2             824.21
Queue.push_back/2           84.92 - 9.71x slower +10.56 ms
:queue.in/2 - async         66.85 - 12.33x slower +13.75 ms
:queue.in/2 - sync          10.84 - 76.07x slower +91.08 ms

##### With input 10_000 #####
Name                          ips        average  deviation         median         99th %
Queue.extend/2            7539.52       0.133 ms    ±61.20%       0.126 ms       0.169 ms
Queue.push_back/2          851.82        1.17 ms     ±1.63%        1.17 ms        1.23 ms
:queue.in/2 - async        681.45        1.47 ms     ±6.91%        1.46 ms        1.74 ms
:queue.in/2 - sync         108.14        9.25 ms     ±0.79%        9.25 ms        9.54 ms

Comparison: 
Queue.extend/2            7539.52
Queue.push_back/2          851.82 - 8.85x slower +1.04 ms
:queue.in/2 - async        681.45 - 11.06x slower +1.33 ms
:queue.in/2 - sync         108.14 - 69.72x slower +9.11 ms

##### With input 1_000 #####
Name                          ips        average  deviation         median         99th %
Queue.extend/2           332.38 K        3.01 μs   ±515.70%        2.75 μs           7 μs
:queue.in/2 - async      139.68 K        7.16 μs    ±46.83%        7.08 μs        9.29 μs
Queue.push_back/2         85.18 K       11.74 μs    ±20.60%       11.42 μs       18.92 μs
:queue.in/2 - sync        10.29 K       97.21 μs    ±33.19%       93.50 μs      303.32 μs

Comparison: 
Queue.extend/2           332.38 K
:queue.in/2 - async      139.68 K - 2.38x slower +4.15 μs
Queue.push_back/2         85.18 K - 3.90x slower +8.73 μs
:queue.in/2 - sync        10.29 K - 32.31x slower +94.20 μs

##### With input 1_000_000 #####
Name                          ips        average  deviation         median         99th %
Queue.extend/2              64.24       15.57 ms     ±6.20%       15.58 ms       19.04 ms
Queue.push_back/2            8.42      118.74 ms     ±1.04%      118.63 ms      123.07 ms
:queue.in/2 - async          6.83      146.46 ms     ±2.75%      147.07 ms      155.89 ms
:queue.in/2 - sync           1.06      941.36 ms     ±0.35%      942.20 ms      944.10 ms

Comparison: 
Queue.extend/2              64.24
Queue.push_back/2            8.42 - 7.63x slower +103.17 ms
:queue.in/2 - async          6.83 - 9.41x slower +130.89 ms
:queue.in/2 - sync           1.06 - 60.47x slower +925.79 ms
```

## Design 

TODO