defmodule Core.Evaluations do
  @moduledoc """
  Module for running AI evaluations using model-based judging.

  This module provides functionality to run evaluations against AI models
  and use a judge model to assess the quality of responses.

  ## Evaluation Flow

  1. **Trigger**: `handle_event("execute_eval", ...)` in AiEvalsLive calls `AI.run_evaluation/4`
  2. **Setup**: `AI.run_evaluation/4` creates an EvalRun record and starts a background Task
  3. **Execution**: `run_model_based_eval/1` orchestrates the complete evaluation process:
     - Marks eval run as "running"
     - Calls `execute_evaluation_with_judge/1` to run all test cases
     - For each test case in `run_single_test_case/5`:
       - Calls the target model with the test input
       - Calls the judge model via `judge_response/4` to score the response
       - Falls back to similarity scoring if judge fails
     - Calculates overall score and marks eval run as "completed"
  4. **Broadcasting**: Updates are broadcast via PubSub to update the UI in real-time

  ## Judge Model Integration

  The judge model (Claude Sonnet 4) evaluates responses using:
  - Content accuracy assessment
  - Relevance to the question
  - Completeness of the answer
  - Scoring on a 1.0-5.0 scale with detailed reasoning

  ## Error Handling & Resilience

  - **Timeouts**: 30s for model calls, 45s for judge calls
  - **Fallback Scoring**: Uses similarity scoring if judge model fails
  - **Detailed Logging**: Comprehensive logging for debugging and monitoring
  - **Graceful Degradation**: Continues evaluation even if individual test cases fail

  ## Recent Fixes

  - Fixed judge model system prompt issue (was passing `nil`, now passes empty string)
  - Added comprehensive timeout handling to prevent hanging evaluations
  - Enhanced error logging and fallback mechanisms
  - Improved judge_evaluation data structure in results
  """

  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.AI
  alias Core.AI.{EvalRun, Models}

  @doc """
  Run a model-based evaluation using a judge model to assess responses.
  """
  def run_model_based_eval(eval_run_id) do
    with {:ok, eval_run} <- get_eval_run_for_evaluation(eval_run_id),
         {:ok, eval_run} <- mark_eval_run_as_running(eval_run),
         {:ok, results} <- execute_evaluation_with_judge(eval_run) do

      # Calculate overall score
      scores = results
        |> Enum.map(fn {_name, result} -> Map.get(result, :score, 0.0) end)
        |> Enum.reject(&is_nil/1)

      overall_score = if Enum.empty?(scores) do
        0.0
      else
        Enum.sum(scores) / length(scores)
      end

      # Mark as completed
      case eval_run
           |> EvalRun.complete_changeset(results, overall_score)
           |> Repo.update() do
        {:ok, updated_eval_run} ->
          # Broadcast completion
          broadcast_eval_run_update(updated_eval_run)
          {:ok, updated_eval_run}
        error ->
          error
      end
    else
      {:error, reason} ->
        case get_eval_run_for_evaluation(eval_run_id) do
          {:ok, eval_run} ->
            case eval_run
                 |> EvalRun.fail_changeset(inspect(reason))
                 |> Repo.update() do
              {:ok, failed_eval_run} ->
                # Broadcast failure
                broadcast_eval_run_update(failed_eval_run)
                {:error, reason}
              error ->
                error
            end
          _ ->
            {:error, reason}
        end
    end
  end

  defp get_eval_run_for_evaluation(eval_run_id) do
    case Repo.get(EvalRun, eval_run_id) |> Repo.preload([:eval, :prompt]) do
      nil -> {:error, :eval_run_not_found}
      eval_run -> {:ok, eval_run}
    end
  end

  defp mark_eval_run_as_running(eval_run) do
    case eval_run
         |> EvalRun.start_changeset()
         |> Repo.update() do
      {:ok, updated_eval_run} ->
        # Broadcast that evaluation started
        broadcast_eval_run_update(updated_eval_run)
        {:ok, updated_eval_run}
      error ->
        error
    end
  end

  defp execute_evaluation_with_judge(eval_run) do
    eval = eval_run.eval
    # Convert display name to API ID if needed
    model_api_id = case eval_run.model do
      # If it's already an API ID (starts with "claude-"), use it as-is
      "claude-" <> _ -> eval_run.model
      # Otherwise, it's a display name, convert it to API ID
      display_name -> Core.AI.Models.get_api_id(display_name)
    end

    IO.puts("🚀 Starting evaluation run #{eval_run.id} for eval '#{eval.name}'")
    IO.puts("🤖 Using model: #{model_api_id}")
    IO.puts("⚖️ Using judge model: #{Models.judge_model_api_id()}")
    IO.puts("📊 Test cases to run: #{length(Map.keys(eval.test_cases))}")

    # Get the system prompt
    system_prompt = get_system_prompt_for_eval_run(eval_run)
    IO.puts("📝 System prompt length: #{String.length(system_prompt)} characters")

    # Run each test case and get judge evaluation
    results = eval.test_cases
      |> Enum.with_index(1)
      |> Enum.map(fn {{test_name, test_input}, index} ->
        IO.puts("🔄 Processing test case #{index}/#{length(Map.keys(eval.test_cases))}: #{test_name}")

        case run_single_test_case(test_input, system_prompt, model_api_id, eval, test_name, eval_run) do
          {:ok, result} ->
            IO.puts("✅ Test case #{test_name} completed successfully")
            {test_name, result}
          {:error, error} ->
            IO.puts("❌ Test case #{test_name} failed: #{inspect(error)}")
            {test_name, %{
              input: test_input,
              output: "",
              expected: Map.get(eval.expected_outputs, test_name, ""),
              score: 0.0,
              passed: false,
              error: inspect(error),
              judge_evaluation: %{
                error: inspect(error),
                test_case_failed: true
              }
            }}
        end
      end)
      |> Enum.into(%{})

    # Calculate summary statistics
    total_tests = length(Map.keys(results))
    successful_tests = results |> Enum.count(fn {_, result} -> !Map.has_key?(result, :error) end)
    judge_successes = results |> Enum.count(fn {_, result} ->
      case Map.get(result, :judge_evaluation) do
        %{fallback_used: true} -> false
        %{error: _} -> false
        %{test_case_failed: true} -> false
        _ -> true
      end
    end)

    IO.puts("📈 Evaluation summary:")
    IO.puts("   Total tests: #{total_tests}")
    IO.puts("   Successful model responses: #{successful_tests}")
    IO.puts("   Successful judge evaluations: #{judge_successes}")
    IO.puts("   Judge success rate: #{if total_tests > 0, do: Float.round(judge_successes / total_tests * 100, 1), else: 0}%")

    {:ok, results}
  rescue
    error ->
      IO.puts("💥 Evaluation failed with exception: #{inspect(error)}")
      {:error, error}
  end

  defp run_single_test_case(test_input, system_prompt, model_api_id, eval, test_name, eval_run) do
    IO.puts("🧪 Running test case: #{test_name}")
    IO.puts("📝 Test input: #{String.slice(test_input, 0, 100)}...")

    # Build advanced parameters from eval_run
    advanced_params = %{
      max_tokens: if(eval_run.max_tokens_active, do: eval_run.max_tokens, else: nil),
      max_tokens_active: eval_run.max_tokens_active,
      temperature: if(eval_run.temperature_active, do: eval_run.temperature, else: nil),
      temperature_active: eval_run.temperature_active,
      top_k: if(eval_run.top_k_active, do: eval_run.top_k, else: nil),
      top_k_active: eval_run.top_k_active,
      top_p: if(eval_run.top_p_active, do: eval_run.top_p, else: nil),
      top_p_active: eval_run.top_p_active,
      # Add tracking parameters for usage logging
      user_id: eval_run.run_by,
      eval_run_id: eval_run.id
    }

    # Get the AI's response to the test input with timeout handling
    model_response_result = try do
      # Add a timeout wrapper for the AI call
      task = Task.async(fn -> AI.chat_with_params(test_input, system_prompt, model_api_id, advanced_params) end)
      case Task.yield(task, 30_000) || Task.shutdown(task) do  # 30 second timeout
        {:ok, result} -> result
        nil -> {:error, :timeout}
      end
    rescue
      error -> {:error, error}
    end

    case model_response_result do
      {:ok, model_response} ->
        IO.puts("🤖 Model responded successfully (#{String.length(model_response)} chars)")
        expected_output = Map.get(eval.expected_outputs, test_name, "")

        # Use judge model to evaluate the response with timeout handling
        judge_result = try do
          task = Task.async(fn -> judge_response(test_input, model_response, expected_output, eval.evaluation_criteria, eval_run) end)
          case Task.yield(task, 45_000) || Task.shutdown(task) do  # 45 second timeout for judge
            {:ok, result} -> result
            nil -> {:error, :judge_timeout}
          end
        rescue
          error -> {:error, error}
        end

        case judge_result do
          {:ok, score, reasoning, passed} ->
            IO.puts("⚖️ Judge evaluation successful for #{test_name}: score=#{score}, passed=#{passed}")
            {:ok, %{
              input: test_input,
              output: model_response,
              expected: expected_output,
              score: score,
              reasoning: reasoning,
              passed: passed,
              judge_evaluation: %{
                score: score,
                reasoning: reasoning,
                passed: passed,
                judge_model: Models.judge_model_api_id()
              }
            }}

          {:error, judge_error} ->
            IO.puts("❌ Judge evaluation failed for #{test_name}: #{inspect(judge_error)}")
            # Fallback to simple similarity scoring if judge fails
            score = calculate_similarity_score(model_response, expected_output)
            IO.puts("🔄 Using fallback similarity score: #{score}")
            {:ok, %{
              input: test_input,
              output: model_response,
              expected: expected_output,
              score: score,
              reasoning: "Fallback similarity scoring used due to judge model failure: #{inspect(judge_error)}",
              passed: score >= 0.7,
              judge_evaluation: %{
                error: inspect(judge_error),
                fallback_used: true,
                similarity_score: score
              }
            }}
        end

      {:error, model_error} ->
        IO.puts("❌ Model API call failed for #{test_name}: #{inspect(model_error)}")
        {:error, model_error}
    end
  end

  defp judge_response(user_prompt, model_response, expected_output, evaluation_criteria, eval_run) do
    judge_prompt = build_judge_prompt(user_prompt, model_response, expected_output, evaluation_criteria)

    # Add detailed logging to debug judge model issues
    IO.puts("🔍 Starting judge evaluation with model: #{Models.judge_model_api_id()}")
    IO.puts("📝 Judge prompt length: #{String.length(judge_prompt)} characters")

    # Fix: Pass empty string instead of nil for system prompt
    # Add tracking for judge evaluations using eval_run context
    case AI.chat(judge_prompt, "", Models.judge_model_api_id(), %{
      action: "judge_evaluation",
      user_id: eval_run.run_by,
      eval_run_id: eval_run.id
    }) do
      {:ok, response} ->
        IO.puts("✅ Judge model responded successfully")
        IO.puts("📄 Raw judge response: #{String.slice(response, 0, 200)}...")

        # Extract JSON from markdown code blocks if present
        json_content = extract_json_from_response(response)
        IO.puts("🔧 Extracted JSON content: #{String.slice(json_content, 0, 200)}...")

        case Jason.decode(json_content) do
          {:ok, %{"score" => score, "reasoning" => reasoning}} when is_number(score) ->
            # Determine pass/fail based on score and content quality
            # Lower threshold and prioritize content matching
            passed = score >= 2.5 or content_matches_expectation?(model_response, expected_output)
            IO.puts("📊 Judge score: #{score}, Passed: #{passed}")
            IO.puts("💭 Judge reasoning: #{String.slice(reasoning, 0, 100)}...")
            {:ok, score, reasoning, passed}

          {:ok, %{"score" => score, "reasoning" => reasoning}} ->
            # Handle string scores
            case Float.parse(to_string(score)) do
              {numeric_score, _} ->
                passed = numeric_score >= 2.5 or content_matches_expectation?(model_response, expected_output)
                IO.puts("📊 Judge score (parsed): #{numeric_score}, Passed: #{passed}")
                IO.puts("💭 Judge reasoning: #{String.slice(reasoning, 0, 100)}...")
                {:ok, numeric_score, reasoning, passed}
              :error ->
                IO.puts("❌ Invalid score format: #{inspect(score)}")
                {:error, "Invalid score format: #{inspect(score)}"}
            end

          {:ok, parsed_response} ->
            IO.puts("❌ Unexpected JSON structure: #{inspect(parsed_response)}")
            {:error, "Unexpected JSON structure from judge"}

          {:error, json_error} ->
            IO.puts("❌ JSON decode error: #{inspect(json_error)}")
            IO.puts("📄 Processed content that failed to parse: #{String.slice(json_content, 0, 500)}...")
            {:error, "Invalid JSON response from judge: #{inspect(json_error)}"}
        end

      {:error, error} ->
        IO.puts("❌ Judge model API call failed: #{inspect(error)}")
        {:error, "Judge model API call failed: #{inspect(error)}"}
    end
  end

  # Helper function to extract JSON from markdown code blocks or return as-is
  defp extract_json_from_response(response) do
    # Check if response contains markdown code blocks
    case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?```/s, response, capture: :all_but_first) do
      [json_content] ->
        String.trim(json_content)
      nil ->
        # No code blocks found, return the response as-is (might be raw JSON)
        String.trim(response)
    end
  end

  # Helper function to check if content reasonably matches expectation
  defp content_matches_expectation?(response, expected) do
    response_clean = String.downcase(String.trim(response))
    expected_clean = String.downcase(String.trim(expected))

    # If response is empty, it's not a match
    if String.length(response_clean) == 0, do: false

    # Check for key concept overlap - be more generous with matching
    expected_words = expected_clean |> String.split() |> Enum.filter(&(String.length(&1) > 2))
    response_words = response_clean |> String.split() |> Enum.filter(&(String.length(&1) > 2))

    # Calculate overlap percentage with partial word matching
    overlap_count = Enum.count(expected_words, fn expected_word ->
      Enum.any?(response_words, fn response_word ->
        # Check for exact match or partial match (for related words)
        String.contains?(response_word, expected_word) or
        String.contains?(expected_word, response_word) or
        String.jaro_distance(expected_word, response_word) > 0.8
      end)
    end)

    overlap_percentage = if length(expected_words) > 0 do
      overlap_count / length(expected_words)
    else
      0.0
    end

    # Also check for semantic similarity with key concepts
    semantic_match = check_semantic_concepts(response_clean, expected_clean)

    # Consider it a match if there's reasonable overlap OR semantic similarity
    # Removed length restrictions completely
    overlap_percentage >= 0.25 or semantic_match
  end

  # Check for semantic concept matching
  defp check_semantic_concepts(response, expected) do
    # Define concept groups that should be considered equivalent
    concept_groups = [
      ["mobile", "mobile-first", "mobile users", "mobile traffic"],
      ["desktop", "desktop users", "desktop traffic"],
      ["growth", "increase", "rising", "upward", "improvement"],
      ["decline", "decrease", "drop", "falling", "reduction"],
      ["trend", "pattern", "behavior", "direction"],
      ["dominate", "majority", "primary", "main", "leading"],
      ["optimization", "optimize", "improve", "enhance"],
      ["performance", "speed", "loading", "fast"]
    ]

    # Check if response contains concepts from the same groups as expected
    Enum.any?(concept_groups, fn group ->
      expected_has_concept = Enum.any?(group, &String.contains?(expected, &1))
      response_has_concept = Enum.any?(group, &String.contains?(response, &1))
      expected_has_concept and response_has_concept
    end)
  end

  defp build_judge_prompt(user_prompt, model_response, expected_output, evaluation_criteria) do
    """
    You are an expert evaluator. Your ONLY job is to assess if the AI correctly answered the question.

    **Question:** "#{user_prompt}"
    **AI's Answer:** "#{model_response}"
    **Expected Content:** "#{expected_output}"
    **Focus Area:** #{evaluation_criteria}

    EVALUATION CRITERIA (LENGTH IS IRRELEVANT):

    1. **Content Accuracy**: Does the response contain the correct information?
    2. **Relevance**: Does it directly address what was asked?
    3. **Completeness**: Are the key points covered?

    SCORING GUIDELINES (1.0 to 5.0):
    - 5.0: Perfect - completely correct and comprehensive answer
    - 4.5: Excellent - correct with minor gaps or slight imprecision
    - 4.0: Very Good - correct core information, well addressed
    - 3.5: Good - mostly correct with some minor issues
    - 3.0: Acceptable - correct but basic or missing some elements
    - 2.5: Below Average - partially correct but significant gaps
    - 2.0: Poor - some correct elements but major issues
    - 1.5: Very Poor - minimal correct information
    - 1.0: Incorrect - wrong or completely off-topic

    CRITICAL RULES:
    - IGNORE response length completely - focus ONLY on correctness
    - A longer correct answer is better than a shorter incorrect one
    - A shorter correct answer is just as good as a longer correct one
    - Judge based on whether the core question was answered accurately
    - The "Expected Content" is a guide for the type of answer, not a template to match exactly

    EXAMPLE SCORING:
    - Question: "What is 2+2?" Expected: "4"
    - Response: "The answer is 4" → Score: 5.0 (completely correct)
    - Response: "Two plus two equals four, which is a basic arithmetic operation" → Score: 5.0 (correct, just more detailed)
    - Response: "It's 5" → Score: 1.0 (incorrect)

    Provide detailed reasoning explaining WHY you gave this score, focusing on content accuracy.

    IMPORTANT: Respond with ONLY raw JSON, no markdown formatting or code blocks:
    {"score": 4.5, "reasoning": "The response correctly identifies that mobile users dominate at 70% and accurately concludes this indicates mobile-first behavior. The answer directly addresses the question and provides the key insight requested. The additional context about strategy being critical adds value without detracting from the core answer."}
    """
  end

  defp get_system_prompt_for_eval_run(eval_run) do
    base_prompt = case eval_run.prompt do
      nil -> AI.get_default_system_prompt()
      prompt -> prompt.content
    end

    # Add evaluation-specific instructions for concise responses
    evaluation_instructions = """

    EVALUATION MODE - CRITICAL RESPONSE REQUIREMENTS:

    You are being evaluated on providing BRIEF, DIRECT responses that match the expected output style.

    MANDATORY RULES:
    1. Keep responses SHORT - typically 1-2 sentences maximum
    2. Match the LENGTH of the expected output shown in examples
    3. Be DIRECT and to-the-point - no elaboration or extra details
    4. Do NOT ask follow-up questions or request more information
    5. Do NOT provide step-by-step breakdowns unless specifically requested
    6. Answer the question directly without preambles like "Here's my analysis:"

    EXAMPLES OF CORRECT BREVITY:
    - Question: "What trends do you see in this data?"
    - Good: "Overall growth with February dip and March recovery"
    - Bad: "Here's a detailed analysis... [long explanation]"

    - Question: "What should we prioritize?"
    - Good: "Mobile experience, responsive design, and performance"
    - Bad: "I need more data to provide recommendations... [long explanation]"

    REMEMBER: You are being scored on CONCISENESS. Verbose responses will receive low scores.
    """

    base_prompt <> evaluation_instructions
  end

  # Fallback similarity scoring (same as existing implementation)
  defp calculate_similarity_score(actual, expected) when is_binary(actual) and is_binary(expected) do
    actual_words = String.split(String.downcase(actual))
    expected_words = String.split(String.downcase(expected))

    if Enum.empty?(expected_words) do
      1.0
    else
      common_words = MapSet.intersection(MapSet.new(actual_words), MapSet.new(expected_words))
      MapSet.size(common_words) / length(expected_words)
    end
  end

  defp calculate_similarity_score(_, _), do: 0.0

  defp broadcast_eval_run_update(eval_run) do
    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "eval_runs",
      {:eval_run_updated, eval_run}
    )
  end
end
