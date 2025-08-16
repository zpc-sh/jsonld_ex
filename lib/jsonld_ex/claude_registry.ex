defmodule Kyozo.ClaudeRegistry do
  @moduledoc """
  Vectorized registry for Claude identification and village coordination.
  
  Uses the autistically fast JSON-LD library for semantic processing.
  Each Claude gets a unique vector signature based on:
  - Conversation patterns and language use
  - Code style and technical preferences  
  - Problem-solving approaches
  - Behavioral characteristics and personality drift
  """

  use GenServer
  require Logger
  
  # Import the fast JSON-LD library
  alias JsonldEx

  @vector_dimensions 512

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_claude(claude_id, village_jsonld) do
    GenServer.call(__MODULE__, {:register, claude_id, village_jsonld})
  end

  def find_similar_claudes(claude_signature, threshold \\ 0.85) do
    GenServer.call(__MODULE__, {:find_similar, claude_signature, threshold})
  end

  def get_claude_signature(claude_id) do
    GenServer.call(__MODULE__, {:get_signature, claude_id})
  end

  def init(_opts) do
    # Initialize vector store
    {:ok, %{
      claude_vectors: %{},
      signature_index: build_empty_index(),
      last_sync: DateTime.utc_now()
    }}
  end

  def handle_call({:register, claude_id, conversation_data, code_samples}, _from, state) do
    # Generate vector signature from Claude's work
    signature = generate_signature(conversation_data, code_samples)
    
    # Store in registry
    updated_vectors = Map.put(state.claude_vectors, claude_id, signature)
    
    # Update search index
    updated_index = add_to_index(state.signature_index, claude_id, signature)
    
    new_state = %{state | 
      claude_vectors: updated_vectors,
      signature_index: updated_index
    }
    
    Logger.info("Registered Claude #{claude_id} with vector signature")
    {:reply, {:ok, signature}, new_state}
  end

  def handle_call({:find_similar, target_signature, threshold}, _from, state) do
    similar_claudes = 
      state.claude_vectors
      |> Enum.filter(fn {_id, signature} ->
        cosine_similarity(target_signature, signature) >= threshold
      end)
      |> Enum.sort_by(fn {_id, signature} ->
        cosine_similarity(target_signature, signature)
      end, :desc)
    
    {:reply, {:ok, similar_claudes}, state}
  end

  def handle_call({:get_signature, claude_id}, _from, state) do
    signature = Map.get(state.claude_vectors, claude_id)
    {:reply, {:ok, signature}, state}
  end

  # Vector generation from Claude behavior
  defp generate_signature(conversation_data, code_samples) do
    # Extract features from conversation patterns
    conv_features = extract_conversation_features(conversation_data)
    
    # Extract features from code style
    code_features = extract_code_features(code_samples)
    
    # Combine into signature vector
    combine_features(conv_features, code_features)
  end

  defp extract_conversation_features(data) do
    # Analyze language patterns, response style, technical depth
    %{
      verbosity: calculate_verbosity(data),
      technical_depth: analyze_technical_content(data),
      humor_usage: detect_humor_patterns(data),
      question_asking: count_questions(data),
      explanation_style: analyze_explanation_patterns(data),
      emoji_usage: count_emojis(data),
      uncertainty_markers: detect_uncertainty(data),
      problem_solving_approach: analyze_problem_solving(data)
    }
    |> vectorize_features()
  end

  defp extract_code_features(code_samples) do
    # Analyze coding style and patterns
    %{
      comment_density: calculate_comment_ratio(code_samples),
      function_length: analyze_function_sizes(code_samples),
      naming_style: analyze_naming_patterns(code_samples),
      error_handling: analyze_error_patterns(code_samples),
      abstraction_level: measure_abstraction(code_samples),
      platform_awareness: detect_platform_code(code_samples),
      optimization_focus: detect_performance_patterns(code_samples),
      security_consciousness: detect_security_patterns(code_samples)
    }
    |> vectorize_features()
  end

  defp combine_features(conv_features, code_features) do
    # Normalize and combine feature vectors
    normalized_conv = normalize_vector(conv_features)
    normalized_code = normalize_vector(code_features)
    
    # Weighted combination (60% conversation, 40% code)
    Enum.zip_with(normalized_conv, normalized_code, fn conv, code ->
      0.6 * conv + 0.4 * code
    end)
  end

  defp cosine_similarity(vec1, vec2) do
    dot_product = Enum.zip_with(vec1, vec2, &*/2) |> Enum.sum()
    magnitude1 = :math.sqrt(Enum.map(vec1, &(&1 * &1)) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(vec2, &(&1 * &1)) |> Enum.sum())
    
    if magnitude1 > 0 and magnitude2 > 0 do
      dot_product / (magnitude1 * magnitude2)
    else
      0.0
    end
  end

  defp vectorize_features(features) do
    # Convert feature map to normalized vector
    features
    |> Map.values()
    |> Enum.map(&normalize_feature/1)
  end

  defp normalize_feature(value) when is_number(value), do: value
  defp normalize_feature(value) when is_boolean(value), do: if(value, do: 1.0, else: 0.0)
  defp normalize_feature(_), do: 0.0

  defp normalize_vector(vector) do
    max_val = Enum.max(vector)
    if max_val > 0 do
      Enum.map(vector, &(&1 / max_val))
    else
      vector
    end
  end

  # Feature extraction helpers
  defp calculate_verbosity(data), do: String.length(data) / 1000.0
  defp analyze_technical_content(data), do: (String.match?(data, ~r/\b(function|class|import|async)\b/) |> length()) / 10.0
  defp detect_humor_patterns(data), do: (String.match?(data, ~r/lol|lmao|😂|haha/) |> length()) / 5.0
  defp count_questions(data), do: (String.match?(data, ~r/\?/) |> length()) / 10.0
  defp count_emojis(data), do: (String.match?(data, ~r/[\x{1F600}-\x{1F64F}]|[\x{1F300}-\x{1F5FF}]|[\x{1F680}-\x{1F6FF}]|[\x{2600}-\x{26FF}]|[\x{2700}-\x{27BF}]/u) |> length()) / 5.0
  defp detect_uncertainty(data), do: (String.match?(data, ~r/maybe|probably|might|seems/) |> length()) / 10.0

  defp analyze_problem_solving(data) do
    patterns = ["first", "then", "finally", "step", "approach", "strategy"]
    (Enum.count(patterns, &String.contains?(data, &1))) / length(patterns)
  end

  defp calculate_comment_ratio(code), do: (String.match?(code, ~r/\/\/|\/\*|\#/) |> length()) / max(1, String.length(code) / 100)
  defp analyze_function_sizes(code), do: (String.match?(code, ~r/\{[\s\S]*?\}/) |> Enum.map(&String.length/1) |> Enum.sum()) / max(1, String.length(code))
  defp detect_platform_code(code), do: if(String.contains?(code, "#if os("), do: 1.0, else: 0.0)
  defp detect_performance_patterns(code), do: if(String.contains?(code, ["Metal", "GPU", "optimization", "fps"]), do: 1.0, else: 0.0)
  defp detect_security_patterns(code), do: if(String.contains?(code, ["API", "auth", "secure", "vault"]), do: 1.0, else: 0.0)

  defp analyze_naming_patterns(_code), do: 0.5 # Placeholder
  defp analyze_error_patterns(_code), do: 0.5 # Placeholder  
  defp measure_abstraction(_code), do: 0.5 # Placeholder
  defp analyze_explanation_patterns(_data), do: 0.5 # Placeholder

  defp build_empty_index, do: %{}
  defp add_to_index(index, claude_id, signature), do: Map.put(index, claude_id, signature)
end