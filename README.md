# Queue

**TODO: Add description**

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


```
at [ 11:00:05 ] ➜ MIX_ENV=test mix run benchmarks.exs
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
Benchmarking Queue.pop_front_n/2 with input 100_000 ...
Benchmarking Queue.pop_front_n/2 with input 10_000 ...
Benchmarking Queue.pop_front_n/2 with input 1_000 ...
Benchmarking Queue.pop_front_n/2 with input 1_000_000 ...
Calculating statistics...
Formatting results...

##### With input 100_000 #####
Name                          ips        average  deviation         median         99th %
:queue.split/2             717.21        1.39 ms    ±84.46%        0.57 ms        3.33 ms
Queue.pop_front_n/2        704.95        1.42 ms    ±49.07%        0.89 ms        3.00 ms
Queue.pop_front/1           16.59       60.27 ms     ±5.44%       59.76 ms       81.74 ms
:queue.out/1                 9.61      104.03 ms     ±3.09%      103.27 ms      120.32 ms

Comparison:
:queue.split/2             717.21
Queue.pop_front_n/2        704.95 - 1.02x slower +0.0243 ms
Queue.pop_front/1           16.59 - 43.23x slower +58.87 ms
:queue.out/1                 9.61 - 74.61x slower +102.63 ms

##### With input 10_000 #####
Name                          ips        average  deviation         median         99th %
Queue.pop_front_n/2        8.35 K       0.120 ms    ±76.03%      0.0929 ms        0.51 ms
:queue.split/2             7.13 K       0.140 ms    ±91.08%      0.0659 ms        0.41 ms
Queue.pop_front/1         0.169 K        5.92 ms     ±6.13%        5.88 ms        7.94 ms
:queue.out/1             0.0956 K       10.46 ms     ±2.17%       10.41 ms       11.46 ms

Comparison:
Queue.pop_front_n/2        8.35 K
:queue.split/2             7.13 K - 1.17x slower +0.0205 ms
Queue.pop_front/1         0.169 K - 49.44x slower +5.80 ms
:queue.out/1             0.0956 K - 87.32x slower +10.34 ms

##### With input 1_000 #####
Name                          ips        average  deviation         median         99th %
Queue.pop_front_n/2      396.27 K        2.52 μs  ±1571.19%        1.88 μs           5 μs
:queue.split/2           235.20 K        4.25 μs  ±1529.56%        1.54 μs        2.42 μs
Queue.pop_front/1         16.50 K       60.61 μs    ±54.12%       58.33 μs       92.76 μs
:queue.out/1               9.70 K      103.12 μs    ±13.98%       98.17 μs      157.39 μs

Comparison:
Queue.pop_front_n/2      396.27 K
:queue.split/2           235.20 K - 1.68x slower +1.73 μs
Queue.pop_front/1         16.50 K - 24.02x slower +58.09 μs
:queue.out/1               9.70 K - 40.86x slower +100.60 μs

##### With input 1_000_000 #####
Name                          ips        average  deviation         median         99th %
Queue.pop_front_n/2         75.09       13.32 ms    ±46.17%        9.18 ms       22.83 ms
:queue.split/2              68.69       14.56 ms    ±72.62%        7.25 ms       32.89 ms
Queue.pop_front/1            1.51      663.27 ms     ±2.29%      659.96 ms      690.96 ms
:queue.out/1                 0.96     1046.28 ms     ±0.35%     1046.27 ms     1049.98 ms

Comparison:
Queue.pop_front_n/2         75.09
:queue.split/2              68.69 - 1.09x slower +1.24 ms
Queue.pop_front/1            1.51 - 49.81x slower +649.95 ms
:queue.out/1                 0.96 - 78.57x slower +1032.96 ms

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
Benchmarking Queue.push_back/2 with input 100_000 ...
Benchmarking Queue.push_back/2 with input 10_000 ...
Benchmarking Queue.push_back/2 with input 1_000 ...
Benchmarking Queue.push_back/2 with input 1_000_000 ...
Benchmarking Queue.push_back_n/2 with input 100_000 ...
Benchmarking Queue.push_back_n/2 with input 10_000 ...
Benchmarking Queue.push_back_n/2 with input 1_000 ...
Benchmarking Queue.push_back_n/2 with input 1_000_000 ...
Calculating statistics...
Formatting results...

##### With input 100_000 #####
Name                          ips        average  deviation         median         99th %
Queue.push_back_n/2        840.03        1.19 ms    ±11.73%        1.17 ms        1.33 ms
Queue.push_back/2           79.77       12.54 ms     ±1.89%       12.45 ms       13.08 ms
:queue.in/2 - async         58.35       17.14 ms     ±4.67%       17.08 ms       19.22 ms
:queue.in/2 - sync           6.70      149.19 ms    ±37.02%      160.72 ms      207.97 ms

Comparison:
Queue.push_back_n/2        840.03
Queue.push_back/2           79.77 - 10.53x slower +11.35 ms
:queue.in/2 - async         58.35 - 14.40x slower +15.95 ms
:queue.in/2 - sync           6.70 - 125.32x slower +148.00 ms

##### With input 10_000 #####
Name                          ips        average  deviation         median         99th %
Queue.push_back_n/2       7882.96       0.127 ms    ±20.92%       0.126 ms       0.151 ms
Queue.push_back/2          807.43        1.24 ms     ±1.23%        1.24 ms        1.32 ms
:queue.in/2 - async        594.25        1.68 ms    ±10.77%        1.68 ms        2.13 ms
:queue.in/2 - sync         102.27        9.78 ms    ±21.70%        9.39 ms       20.92 ms

Comparison:
Queue.push_back_n/2       7882.96
Queue.push_back/2          807.43 - 9.76x slower +1.11 ms
:queue.in/2 - async        594.25 - 13.27x slower +1.56 ms
:queue.in/2 - sync         102.27 - 77.08x slower +9.65 ms

##### With input 1_000 #####
Name                          ips        average  deviation         median         99th %
Queue.push_back_n/2      345.03 K        2.90 μs   ±409.49%        2.75 μs        5.13 μs
:queue.in/2 - async      141.34 K        7.07 μs    ±35.15%           7 μs        9.17 μs
Queue.push_back/2         81.26 K       12.31 μs    ±19.64%       12.04 μs       19.25 μs
:queue.in/2 - sync        10.40 K       96.20 μs    ±19.00%       94.37 μs      115.13 μs

Comparison:
Queue.push_back_n/2      345.03 K
:queue.in/2 - async      141.34 K - 2.44x slower +4.18 μs
Queue.push_back/2         81.26 K - 4.25x slower +9.41 μs
:queue.in/2 - sync        10.40 K - 33.19x slower +93.30 μs

##### With input 1_000_000 #####
Name                          ips        average  deviation         median         99th %
Queue.push_back_n/2         66.64       15.01 ms     ±6.99%       14.34 ms       16.71 ms
Queue.push_back/2            7.85      127.38 ms     ±1.37%      126.80 ms      132.05 ms
:queue.in/2 - async          6.28      159.16 ms     ±2.24%      158.59 ms      164.78 ms
:queue.in/2 - sync           1.05      951.40 ms     ±0.58%      953.10 ms      955.92 ms

Comparison:
Queue.push_back_n/2         66.64
Queue.push_back/2            7.85 - 8.49x slower +112.38 ms
:queue.in/2 - async          6.28 - 10.61x slower +144.15 ms
:queue.in/2 - sync           1.05 - 63.40x slower +936.40 ms

```
