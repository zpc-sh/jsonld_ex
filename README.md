# JsonldEx

High-performance JSON-LD processing library for Elixir with Rust NIF backend.

## Features

- Full JSON-LD 1.1 specification support
- High-performance Rust NIF backend
- Semantic versioning with dependency resolution 
- Graph operations and query capabilities
- Context caching and optimization
- Batch processing for multiple operations

## Installation

Add `jsonld_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jsonld_ex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Expand a JSON-LD document
doc = %{"@context" => "https://schema.org/", "@type" => "Person", "name" => "Jane"}
{:ok, expanded} = JsonldEx.expand(doc)

# Compact with a context
context = %{"name" => "https://schema.org/name"}
{:ok, compacted} = JsonldEx.compact(expanded, context)
```

## License

MIT

