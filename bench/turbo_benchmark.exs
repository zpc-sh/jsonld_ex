#!/usr/bin/env mix run

# Benchmark our turbo optimizations

defmodule TurboBenchmark do
  def run do
    IO.puts("=" <> String.duplicate("=", 60))
    IO.puts("JsonldEx Turbo Optimizations Benchmark")
    IO.puts("=" <> String.duplicate("=", 60))
    
    # Test data
    doc = %{
      "@context" => %{
        "name" => "http://schema.org/name",
        "age" => "http://schema.org/age",
        "knows" => "http://schema.org/knows"
      },
      "@type" => "Person",
      "name" => "John Doe",
      "age" => 30,
      "knows" => [
        %{"@type" => "Person", "name" => "Jane"},
        %{"@type" => "Person", "name" => "Bob"}
      ]
    }
    
    # Warm up
    JsonldEx.expand(doc)
    JsonldEx.expand_turbo(doc)
    
    IO.puts("\n📈 SINGLE DOCUMENT BENCHMARKS")
    IO.puts("-" <> String.duplicate("-", 50))
    
    # Regular expansion
    {regular_time, {:ok, _}} = :timer.tc(fn ->
      JsonldEx.expand(doc)
    end)
    
    # Turbo expansion  
    {turbo_time, {:ok, _}} = :timer.tc(fn ->
      JsonldEx.expand_turbo(doc)
    end)
    
    speedup = regular_time / turbo_time
    
    IO.puts("Regular expand: #{format_time(regular_time)}")
    IO.puts("Turbo expand:   #{format_time(turbo_time)}")
    IO.puts("🚀 Turbo speedup: #{Float.round(speedup, 2)}x")
    
    # Batch processing benchmark
    documents = Enum.map(1..100, fn i ->
      Map.put(doc, "name", "Person #{i}")
    end)
    
    IO.puts("\n📦 BATCH PROCESSING (100 documents)")
    IO.puts("-" <> String.duplicate("-", 50))
    
    # Sequential processing
    {sequential_time, _} = :timer.tc(fn ->
      Enum.map(documents, &JsonldEx.expand_turbo/1)
    end)
    
    # Elixir-side concurrent batch processing
    {batch_time, _} = :timer.tc(fn ->
      JsonldEx.expand_batch(documents)
    end)
    
    # Rust-side parallel batch processing with SIMD
    {rust_batch_time, _} = :timer.tc(fn ->
      JsonldEx.expand_batch_rust(documents)
    end)
    
    batch_speedup = sequential_time / batch_time
    rust_batch_speedup = sequential_time / rust_batch_time
    
    IO.puts("Sequential:         #{format_time(sequential_time)}")
    IO.puts("Elixir batch (#{System.schedulers_online()} cores):  #{format_time(batch_time)}")
    IO.puts("🚀 Elixir batch speedup: #{Float.round(batch_speedup, 2)}x")
    IO.puts("Rust batch (SIMD):   #{format_time(rust_batch_time)}")
    IO.puts("🚀 Rust batch speedup:  #{Float.round(rust_batch_speedup, 2)}x")
    
    IO.puts("\n" <> "=" <> String.duplicate("=", 60))
    IO.puts("SUMMARY:")
    IO.puts("• Zero-copy processing: #{Float.round(speedup, 1)}x faster")
    IO.puts("• Elixir concurrent:    #{Float.round(batch_speedup, 1)}x faster") 
    IO.puts("• Rust SIMD parallel:   #{Float.round(rust_batch_speedup, 1)}x faster")
    IO.puts("• Best combined:        #{Float.round(speedup * max(batch_speedup, rust_batch_speedup), 1)}x faster")
    IO.puts("=" <> String.duplicate("=", 60))
  end
  
  defp format_time(microseconds) when microseconds < 1_000 do
    "#{microseconds}μs"
  end
  
  defp format_time(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1_000, 1)}ms"
  end
  
  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1_000_000, 2)}s"
  end
end

TurboBenchmark.run()