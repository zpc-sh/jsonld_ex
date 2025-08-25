#!/usr/bin/env mix run

# Simple benchmark comparing JsonldEx (Rust) vs JSON.LD (pure Elixir)

sample_data = %{
  "@context" => %{
    "name" => "http://schema.org/name",
    "age" => "http://schema.org/age",
    "Person" => "http://schema.org/Person"
  },
  "@type" => "Person",
  "name" => "John Doe",
  "age" => 30
}

sample_json_string = Jason.encode!(sample_data)

# Test data sizes
small_data = sample_data
small_data_json = sample_json_string

# Benchmarking function
benchmark = fn name, data, fun ->
  start_time = System.monotonic_time(:microsecond)
  
  result = try do
    case fun.(data) do
      {:ok, _} -> :success
      _ -> :error
    end
  rescue
    e -> 
      IO.puts("Error in #{name}: #{inspect(e)}")
      :error
  end
  
  end_time = System.monotonic_time(:microsecond)
  duration = end_time - start_time
  
  IO.puts("#{name}: #{duration}μs (#{result})")
  duration
end

IO.puts("=== JSON-LD Expansion Benchmark ===")

# Test both implementations
IO.puts("\n--- Small Data ---")

# Test Rust implementation (expects JSON string)
rust_time = benchmark.("JsonldEx (Rust)", small_data_json, fn data ->
  JsonldEx.Native.expand(data, [])
end)

# Test Elixir implementation (expects Elixir map)
elixir_time = benchmark.("JSON.LD (Elixir)", small_data, fn data ->
  try do
    {:ok, JSON.LD.expand(data)}
  rescue
    e -> {:error, e}
  end
end)

if rust_time > 0 and elixir_time > 0 do
  speedup = elixir_time / rust_time
  IO.puts("Speedup: #{Float.round(speedup, 2)}x")
  
  IO.puts("\n=== Summary ===")
  if speedup > 1 do
    IO.puts("✅ Your Rust implementation is #{Float.round(speedup, 1)}x faster!")
  else
    IO.puts("⚠️  The Elixir implementation is faster by #{Float.round(1/speedup, 1)}x")
  end
else
  IO.puts("❌ Could not compare due to errors")
end