defmodule Core.AI do
  @moduledoc """
  AI module for interacting with both Anthropic Claude and OpenAI models.

  This module provides a unified interface for AI chat functionality,
  automatically routing requests to the appropriate provider based on the model.

  ## Supported Providers

  - **Anthropic**: Claude models (claude-*)
  - **OpenAI**: GPT models (gpt-*)

  ## Configuration

  ### Development
  - Set `ANTHROPIC_API_KEY` environment variable for Claude models
  - Set `OPENAI_API_KEY` environment variable for GPT models

  ### Production
  Both API keys are required in production and validated at runtime.

  ## Examples

      # Using default Anthropic model
      {:ok, response} = Core.AI.chat("Hello, how are you?")

      # Using specific OpenAI model
      {:ok, response} = Core.AI.chat("Hello!", "You are helpful.", "gpt-4o")

      # Using specific Anthropic model
      {:ok, response} = Core.AI.chat("Hello!", "You are helpful.", "claude-3-5-sonnet-20241022")
  """

  import Ecto.Query
  alias Core.Repo
  alias Core.AI.{Conversation, Message, Prompt, Eval, EvalRun, Models, Usage}

  @default_system_prompt """
  You are a helpful AI assistant integrated into a Phoenix application.
  You provide clear, concise, and accurate responses while maintaining a professional tone.
  When discussing code or technical topics, you provide practical examples and explanations.
  """

  @doc """
  Initialize an Anthropix client using the configured API key.
  """
  def client do
    case Application.get_env(:anthropix, :api_key) do
      nil ->
        raise "ANTHROPIC_API_KEY environment variable is not set. Please set it in your environment or config."
      api_key when is_binary(api_key) and api_key != "" ->
        Anthropix.init(api_key)
      _ ->
        raise "Invalid ANTHROPIC_API_KEY. Please check your environment variable."
    end
  end

  @doc """
  Initialize an OpenaiEx client using the OPENAI_API_KEY environment variable.
  """
  def openai_client do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        raise "OPENAI_API_KEY environment variable is not set. Please set it in your environment."
      api_key when is_binary(api_key) and api_key != "" ->
        OpenaiEx.new(api_key)
      _ ->
        raise "Invalid OPENAI_API_KEY. Please check your environment variable."
    end
  end

  # ============================================================================
  # Conversation Management
  # ============================================================================

  @doc """
  Create a new conversation for a user.
  """
  def create_conversation(user_id, title, system_prompt \\ @default_system_prompt, advanced_params \\ %{}) do
    attrs = %{
      title: title,
      system_prompt: system_prompt,
      user_id: user_id
    }
    |> Map.merge(advanced_params)

    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a conversation by ID, ensuring it belongs to the specified user.
  """
  def get_conversation(conversation_id, user_id) do
    Conversation
    |> where([c], c.id == ^conversation_id and c.user_id == ^user_id)
    |> preload([:messages, :selected_prompt])
    |> Repo.one()
  end

  @doc """
  Lists all conversations for a user, ordered by most recent first.
  """
  def list_conversations(user_id) do
    Conversation
    |> where([c], c.user_id == ^user_id and c.archived == false)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Returns the total count of conversations.
  """
  def count_conversations do
    try do
      Repo.aggregate(Conversation, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Returns the total count of conversations with optional filtering.

  ## Options

    * `:archived` - Filter by archived status (true/false)
    * `:user_id` - Filter by specific user
  """
  def count_conversations(opts) do
    try do
      archived = Keyword.get(opts, :archived)
      user_id = Keyword.get(opts, :user_id)

      query = Conversation

      query = if archived != nil do
        where(query, [c], c.archived == ^archived)
      else
        query
      end

      query = if user_id do
        where(query, [c], c.user_id == ^user_id)
      else
        query
      end

      Repo.aggregate(query, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Update a conversation's title.
  """
  def update_conversation_title(conversation_id, user_id, title) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :not_found}
      conversation ->
        conversation
        |> Conversation.changeset(%{title: title})
        |> Repo.update()
    end
  end

  @doc """
  Auto-generate a title for a conversation based on the first user message.
  """
  def auto_generate_conversation_title(conversation_id, user_id, first_message) do
    title_prompt = """
    Based on this user message, generate a short, descriptive title (3-6 words max) for a chat conversation.
    The title should capture the main topic or intent. Respond with ONLY the title, no quotes or extra text.

    User message: #{first_message}
    """

    case chat(title_prompt, "You are a helpful assistant that creates concise, descriptive titles.", "claude-3-5-haiku-20241022") do
      {:ok, generated_title} ->
        # Clean up the title (remove quotes, trim, limit length)
        clean_title = generated_title
          |> String.trim()
          |> String.replace(~r/^["']|["']$/, "")  # Remove surrounding quotes
          |> String.slice(0, 50)  # Limit to 50 characters

        update_conversation_title(conversation_id, user_id, clean_title)

      {:error, _reason} ->
        # If auto-generation fails, use a fallback based on the first few words
        fallback_title = first_message
          |> String.split()
          |> Enum.take(4)
          |> Enum.join(" ")
          |> String.slice(0, 30)

        update_conversation_title(conversation_id, user_id, fallback_title)
    end
  end

  @doc """
  Archives a conversation.
  """
  def archive_conversation(conversation_id, user_id) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :conversation_not_found}
      conversation ->
        conversation
        |> Conversation.archive_changeset(true)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a conversation and all its messages.
  """
  def delete_conversation(conversation_id, user_id) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :conversation_not_found}
      conversation ->
        Repo.delete(conversation)
    end
  end

  @doc """
  Update a conversation's advanced AI parameters.
  """
  def update_conversation_advanced_params(conversation_id, user_id, advanced_params) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :conversation_not_found}
      conversation ->
        conversation
        |> Conversation.advanced_params_changeset(advanced_params)
        |> Repo.update()
    end
  end

  @doc """
  Update a conversation's prompt settings.
  """
  def update_conversation_prompt(conversation_id, user_id, prompt_params) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :conversation_not_found}
      conversation ->
        conversation
        |> Conversation.prompt_changeset(prompt_params)
        |> Repo.update()
    end
  end

  # ============================================================================
  # Message Management
  # ============================================================================

  @doc """
  Adds a message to a conversation.
  """
  def add_message(conversation_id, role, content, model \\ nil, metadata \\ %{}, message_params \\ %{}) do
    attrs = %{
      conversation_id: conversation_id,
      role: role,
      content: content,
      model: model,
      metadata: metadata
    }
    |> Map.merge(message_params)

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets all messages for a conversation, ordered by creation time.
  """
  def get_conversation_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the total count of AI messages.
  """
  def count_messages do
    try do
      Repo.aggregate(Message, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Returns the total count of AI messages with optional filtering.

  ## Options

    * `:role` - Filter by message role (:user, :assistant, :system)
    * `:conversation_id` - Filter by specific conversation
  """
  def count_messages(opts) do
    try do
      role = Keyword.get(opts, :role)
      conversation_id = Keyword.get(opts, :conversation_id)

      query = Message

      query = if role do
        where(query, [m], m.role == ^role)
      else
        query
      end

      query = if conversation_id do
        where(query, [m], m.conversation_id == ^conversation_id)
      else
        query
      end

      Repo.aggregate(query, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Gets the latest prompt and eval settings from the last message in a conversation.
  Returns a map with prompt_name and eval_name, or nil if no messages exist.
  """
  def get_latest_prompt_eval_from_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> where([m], not is_nil(m.prompt_name) or not is_nil(m.eval_name))
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> select([m], %{prompt_name: m.prompt_name, eval_name: m.eval_name})
    |> Repo.one()
  end

  @doc """
  Converts messages from the database format to the format expected by Anthropix.
  """
  def messages_to_anthropix_format(messages) do
    messages
    |> Enum.filter(&(&1.role in [:user, :assistant]))
    |> Enum.map(&%{role: Atom.to_string(&1.role), content: &1.content})
  end

  # ============================================================================
  # Helper Functions for Multi-Provider Support
  # ============================================================================

  defp openai_chat_request(model, system_prompt, user_message, opts \\ %{}) do
    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_message}
    ]

    request_params = %{
      model: model,
      messages: messages,
      max_tokens: Map.get(opts, :max_tokens, 4000),
      temperature: Map.get(opts, :temperature, 0.7)
    }

    # Create the request struct
    chat_request = OpenaiEx.Chat.Completions.new(request_params)

    # Make the API call
    openai_client()
    |> OpenaiEx.Chat.Completions.create(chat_request)
  end

  defp openai_chat_request_with_history(model, system_prompt, messages, opts \\ %{}) do
    # Convert messages to OpenAI format and prepend system message
    openai_messages = [%{role: "system", content: system_prompt} | messages]

    request_params = %{
      model: model,
      messages: openai_messages,
      max_tokens: Map.get(opts, :max_tokens, 4000),
      temperature: Map.get(opts, :temperature, 0.7)
    }

    # Create the request struct
    chat_request = OpenaiEx.Chat.Completions.new(request_params)

    # Make the API call
    openai_client()
    |> OpenaiEx.Chat.Completions.create(chat_request)
  end

  # ============================================================================
  # AI Chat Functions (with persistence)
  # ============================================================================

  @doc """
  Stream chat completion for a conversation using the specified model.
  """
  def stream_chat_in_conversation(conversation_id, user_id, user_message, model_api_id, opts \\ %{}) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :conversation_not_found}
      conversation ->
        # Add user message to conversation (no model for user messages)
        {:ok, _user_message} = add_message(conversation_id, "user", user_message)

        # Get all messages for context
        messages = get_conversation_messages(conversation_id)

        # Track start time for usage monitoring
        start_time = System.monotonic_time(:millisecond)

        # Route to appropriate provider based on model
        case Models.get_provider(model_api_id) do
          :anthropic ->
            stream_anthropic_conversation(conversation, messages, user_message, model_api_id, opts, start_time, user_id, conversation_id)

          :openai ->
            stream_openai_conversation(conversation, messages, user_message, model_api_id, opts, start_time, user_id, conversation_id)

          :unknown ->
            {:error, "Unsupported model: #{model_api_id}"}
        end
    end
  end

  # Private function to handle Anthropic streaming
  defp stream_anthropic_conversation(conversation, messages, user_message, model_api_id, opts, start_time, user_id, conversation_id) do
    anthropix_messages = messages_to_anthropix_format(messages)

    # Build chat parameters with defaults
    chat_params = build_anthropic_chat_params(model_api_id, conversation.system_prompt,
                                             anthropix_messages ++ [%{role: "user", content: user_message}],
                                             opts)

    # Stream AI response using Anthropic
    case Anthropix.chat(client(), chat_params) do
      {:ok, stream} ->
        # Include tracking context in the options for complete_streaming_conversation
        tracking_opts = Map.merge(opts, %{
          start_time: start_time,
          user_id: user_id,
          conversation_id: conversation_id,
          action: "stream_chat_conversation"
        })
        {:ok, stream, conversation, model_api_id, tracking_opts}
      {:error, reason} ->
        # Track failed streaming request
        track_chat_completion(
          model_api_id,
          "stream_chat_conversation",
          user_id,
          conversation_id,
          nil,
          start_time,
          {:error, reason},
          opts
        )
        {:error, reason}
    end
  end

  # Private function to handle OpenAI streaming
  defp stream_openai_conversation(conversation, messages, user_message, model_api_id, opts, start_time, user_id, conversation_id) do
    # Convert messages to OpenAI format
    openai_messages = messages_to_openai_format(messages) ++ [%{role: "user", content: user_message}]

    # Build OpenAI chat parameters
    chat_params = build_openai_chat_params(model_api_id, conversation.system_prompt, openai_messages, opts)

    # Create the request struct
    chat_request = OpenaiEx.Chat.Completions.new(chat_params)

    # Stream AI response using OpenAI
    case OpenaiEx.Chat.Completions.create(openai_client(), chat_request, stream: true) do
      {:ok, response} ->
        # OpenaiEx returns a response with a body_stream field for streaming
        # We need to extract the actual stream from the response
        stream = response.body_stream |> Stream.flat_map(& &1)

        # Include tracking context in the options for complete_streaming_conversation
        tracking_opts = Map.merge(opts, %{
          start_time: start_time,
          user_id: user_id,
          conversation_id: conversation_id,
          action: "stream_chat_conversation"
        })
        {:ok, stream, conversation, model_api_id, tracking_opts}
      {:error, reason} ->
        # Track failed streaming request
        track_chat_completion(
          model_api_id,
          "stream_chat_conversation",
          user_id,
          conversation_id,
          nil,
          start_time,
          {:error, reason},
          opts
        )
        {:error, reason}
    end
  end

  # Helper function to convert messages to OpenAI format
  defp messages_to_openai_format(messages) do
    messages
    |> Enum.filter(&(&1.role in [:user, :assistant]))
    |> Enum.map(&%{role: Atom.to_string(&1.role), content: &1.content})
  end

  # Helper function to build Anthropic chat parameters
  defp build_anthropic_chat_params(model_api_id, system_prompt, messages, opts) do
    base_params = %{
      model: model_api_id,
      system: system_prompt,
      messages: messages,
      stream: true
    }

    # Add advanced parameters if they are provided and active
    base_params
    |> maybe_add_param(:max_tokens, opts[:max_tokens], opts[:max_tokens_active])
    |> maybe_add_param(:temperature, opts[:temperature], opts[:temperature_active])
    |> maybe_add_param(:top_k, opts[:top_k], opts[:top_k_active])
    |> maybe_add_param(:top_p, opts[:top_p], opts[:top_p_active])
  end

  # Helper function to build OpenAI chat parameters
  defp build_openai_chat_params(model_api_id, system_prompt, messages, opts) do
    # Prepend system message to OpenAI messages
    openai_messages = [%{role: "system", content: system_prompt} | messages]

    base_params = %{
      model: model_api_id,
      messages: openai_messages,
      stream: true
    }

    # Add advanced parameters if they are provided and active
    # Note: OpenAI supports max_tokens, temperature, and top_p, but NOT top_k
    base_params
    |> maybe_add_param(:max_tokens, opts[:max_tokens], opts[:max_tokens_active])
    |> maybe_add_param(:temperature, opts[:temperature], opts[:temperature_active])
    |> maybe_add_param(:top_p, opts[:top_p], opts[:top_p_active])
    # top_k is not supported by OpenAI API (only Anthropic/Claude)
  end

  defp build_chat_params(model_api_id, system_prompt, messages, opts) do
    # This function is kept for backward compatibility but should use the new provider-specific functions
    case Models.get_provider(model_api_id) do
      :anthropic ->
        build_anthropic_chat_params(model_api_id, system_prompt, messages, opts)
      :openai ->
        # For OpenAI, we need to handle the messages differently
        openai_messages = if is_list(messages) and length(messages) > 0 do
          # Convert from Anthropic format to OpenAI format if needed
          case List.first(messages) do
            %{role: role} when is_binary(role) -> messages  # Already in OpenAI format
            _ -> messages_to_openai_format(messages)  # Convert from DB format
          end
        else
          []
        end
        build_openai_chat_params(model_api_id, system_prompt, openai_messages, opts)
      :unknown ->
        %{error: "Unsupported model: #{model_api_id}"}
    end
  end

  @doc """
  Chat with AI in a conversation context using the conversation's model.
  """
  def chat_in_conversation(conversation_id, user_id, user_message) do
    case get_conversation(conversation_id, user_id) do
      nil ->
        {:error, :conversation_not_found}
      conversation ->
        # Add user message to conversation
        {:ok, _user_message} = add_message(conversation_id, "user", user_message)

        # Get all messages for context
        messages = get_conversation_messages(conversation_id)
        anthropix_messages = messages_to_anthropix_format(messages)

        # Use the conversation's model
        model = conversation.model || Models.default_model_api_id()
        start_time = System.monotonic_time(:millisecond)

        # Get AI response using the conversation's model
        result = Anthropix.chat(client(),
          model: model,
          max_tokens: 4000,
          system: conversation.system_prompt,
          messages: anthropix_messages ++ [%{role: "user", content: user_message}]
        )

        case result do
          {:ok, %{content: [%{text: ai_response}]}} ->
            # Save AI response
            case add_message(conversation_id, "assistant", ai_response, model) do
              {:ok, ai_msg} ->
                # Track usage
                track_chat_completion(
                  model,
                  "chat_conversation",
                  user_id,
                  conversation_id,
                  ai_msg.id,
                  start_time,
                  result
                )
                {:ok, ai_response, conversation}
              error -> error
            end

          error ->
            # Track failed usage
            track_chat_completion(
              model,
              "chat_conversation",
              user_id,
              conversation_id,
              nil,
              start_time,
              error
            )
            error
        end
    end
  end

  @doc """
  Completes a streaming conversation by saving the final AI response with the model used.
  """
  def complete_streaming_conversation(conversation_id, ai_response, model_api_id, opts \\ %{}) do
    # Debug logging
    IO.puts("💾 Completing streaming conversation with response: #{inspect(ai_response)}")
    IO.puts("📏 Response length: #{String.length(ai_response || "")}")

    # Check if response is empty or nil
    if is_nil(ai_response) or String.trim(ai_response) == "" do
      IO.puts("⚠️  Empty AI response detected, skipping database save")
      {:error, :empty_response}
    else
      # Extract active advanced parameters for the message
      active_params = extract_active_advanced_params(opts)

      # Include prompt information
      prompt_params = %{
        prompt_id: opts[:prompt_id]
      }

      # Merge all message parameters
      message_params = Map.merge(active_params, prompt_params)

      # Include advanced parameters in metadata for backward compatibility
      metadata = Map.take(opts, [:max_tokens, :temperature, :top_k, :top_p])

      case add_message(conversation_id, :assistant, ai_response, model_api_id, metadata, message_params) do
        {:ok, ai_message} ->
          # Track usage if we have tracking context from streaming
          if opts[:start_time] && opts[:user_id] && opts[:action] do
            # Create a mock successful response for tracking
            mock_response = {:ok, %{content: [%{text: ai_response}]}}

            track_chat_completion(
              model_api_id,
              opts[:action],
              opts[:user_id],
              conversation_id,
              ai_message.id,
              opts[:start_time],
              mock_response,
              opts
            )
          end

          # Update conversation timestamp (truncate to seconds for Ecto compatibility)
          conversation = Repo.get!(Conversation, conversation_id)
          Repo.update!(Ecto.Changeset.change(conversation, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)))

          {:ok, ai_message}
        {:error, changeset} ->
          IO.puts("❌ Failed to save AI message: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    end
  end

  defp extract_active_advanced_params(opts) do
    %{}
    |> maybe_add_active_param(:max_tokens, opts[:max_tokens], opts[:max_tokens_active])
    |> maybe_add_active_param(:temperature, opts[:temperature], opts[:temperature_active])
    |> maybe_add_active_param(:top_k, opts[:top_k], opts[:top_k_active])
    |> maybe_add_active_param(:top_p, opts[:top_p], opts[:top_p_active])
  end

  defp maybe_add_active_param(params, _key, _value, false), do: params
  defp maybe_add_active_param(params, _key, nil, _active), do: params
  defp maybe_add_active_param(params, key, value, true), do: Map.put(params, key, value)

  # ============================================================================
  # Legacy Functions (for backward compatibility)
  # ============================================================================

  @doc """
  Send a single message to the AI and get a response (non-streaming).
  This is used for evaluations and other non-interactive use cases.
  Supports both Anthropic and OpenAI models.
  """
  def chat(message, system_prompt \\ @default_system_prompt, model \\ nil, opts \\ %{}) do
    model_api_id = if model, do: model, else: Models.default_model_api_id()
    start_time = System.monotonic_time(:millisecond)

    # Route to appropriate provider based on model
    result = case Models.get_provider(model_api_id) do
      :anthropic ->
        Anthropix.chat(client(),
          model: model_api_id,
          system: system_prompt,
          messages: [%{role: "user", content: message}]
        )

      :openai ->
        openai_chat_request(model_api_id, system_prompt, message)

      :unknown ->
        {:error, "Unsupported model: #{model_api_id}"}
    end

    # Track usage if user_id is provided
    if opts[:user_id] do
      track_chat_completion(
        model_api_id,
        "chat",
        opts[:user_id],
        opts[:conversation_id],
        opts[:message_id],
        start_time,
        result,
        opts
      )
    end

    case result do
      {:ok, %{content: [%{text: text}]}} -> {:ok, text}
      {:ok, %{"content" => [%{"text" => text}]}} -> {:ok, text}
      {:ok, %{"choices" => [%{"message" => %{"content" => text}} | _]}} -> {:ok, text}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Send a single message to the AI with advanced parameters and get a response (non-streaming).
  This is used for evaluations and other use cases that need specific AI parameters.
  """
  def chat_with_params(message, system_prompt \\ @default_system_prompt, model \\ nil, advanced_params \\ %{}) do
    model_api_id = if model, do: model, else: Models.default_model_api_id()
    start_time = System.monotonic_time(:millisecond)

    base_params = [
      model: model_api_id,
      system: system_prompt,
      messages: [%{role: "user", content: message}]
    ]

    # Add advanced parameters if they are provided and active
    params = base_params
    |> maybe_add_param_to_keyword(:max_tokens, advanced_params[:max_tokens], advanced_params[:max_tokens_active])
    |> maybe_add_param_to_keyword(:temperature, advanced_params[:temperature], advanced_params[:temperature_active])
    |> maybe_add_param_to_keyword(:top_k, advanced_params[:top_k], advanced_params[:top_k_active])
    |> maybe_add_param_to_keyword(:top_p, advanced_params[:top_p], advanced_params[:top_p_active])

    result = Anthropix.chat(client(), params)

    # Track usage if user_id or eval_run_id is provided
    if advanced_params[:user_id] or advanced_params[:eval_run_id] do
      action = if advanced_params[:eval_run_id], do: "evaluation", else: "chat_with_params"
      track_chat_completion(
        model_api_id,
        action,
        advanced_params[:user_id],
        advanced_params[:conversation_id],
        advanced_params[:message_id],
        start_time,
        result,
        advanced_params
      )
    end

    case result do
      {:ok, %{content: [%{text: text}]}} -> {:ok, text}
      {:ok, %{"content" => [%{"text" => text}]}} -> {:ok, text}
      {:error, error} -> {:error, error}
    end
  end

  defp maybe_add_param_to_keyword(params, _key, _value, false), do: params
  defp maybe_add_param_to_keyword(params, _key, nil, _active), do: params
  defp maybe_add_param_to_keyword(params, key, value, true), do: Keyword.put(params, key, value)

  # Helper function for adding parameters to maps (used in build_*_chat_params functions)
  defp maybe_add_param(params, _key, _value, false), do: params
  defp maybe_add_param(params, _key, nil, _active), do: params
  defp maybe_add_param(params, key, value, true), do: Map.put(params, key, value)

  @doc """
  Send a conversation (list of messages) to Claude.
  Optionally accepts a system prompt to guide the response.

  ## Examples

      messages = [
        %{role: "user", content: "What is 2+2?"},
        %{role: "assistant", content: "2+2 equals 4."},
        %{role: "user", content: "What about 3+3?"}
      ]

      Core.AI.chat_conversation(messages, "You are a math tutor.")
  """
  def chat_conversation(messages, system_prompt \\ @default_system_prompt, model \\ nil) when is_list(messages) do
    model = model || Models.default_model_api_id()
    case Anthropix.chat(client(),
      model: model,
      messages: messages,
      system: system_prompt
    ) do
      {:ok, %{"content" => [%{"text" => text}]}} -> {:ok, text}
      {:ok, response} -> {:ok, extract_text_from_response(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Send a message to Claude with a system prompt.
  This is an alias for chat/2 for backward compatibility.

  ## Examples

      Core.AI.chat_with_system(
        "You are a helpful coding assistant.",
        "How do I create a Phoenix LiveView component?"
      )
  """
  def chat_with_system(system_prompt, user_message, model \\ nil) do
    model = model || Models.default_model_api_id()
    chat(user_message, system_prompt, model)
  end

  @doc """
  Stream a conversation with Claude for real-time responses.
  Optionally accepts a system prompt to guide the response.

  ## Examples

      {:ok, stream} = Core.AI.stream_chat("Tell me a story", "You are a creative storyteller.")

      stream
      |> Stream.each(fn chunk ->
        # Process each chunk of the response
        IO.puts(chunk)
      end)
      |> Stream.run()
  """
  def stream_chat(message, system_prompt \\ @default_system_prompt, model \\ nil) when is_binary(message) do
    model = model || Models.default_model_api_id()
    messages = [%{role: "user", content: message}]

    case Anthropix.chat(client(),
      model: model,
      messages: messages,
      system: system_prompt,
      stream: true
    ) do
      {:ok, stream} ->
        {:ok, Stream.map(stream, &extract_text_from_stream/1)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to extract text from stream chunks - supports both Anthropic and OpenAI
  def extract_text_from_stream(%{"type" => "content_block_delta", "delta" => %{"text" => text}}) do
    # Anthropic format
    text
  end
  def extract_text_from_stream(%{"type" => "message_delta", "delta" => %{"content" => [%{"text" => text}]}}) do
    # Anthropic format
    text
  end
  def extract_text_from_stream(%{"choices" => [%{"delta" => %{"content" => content}} | _]}) when is_binary(content) do
    # OpenAI format
    content
  end
  def extract_text_from_stream(%{"choices" => [%{"delta" => delta} | _]}) do
    # OpenAI format - sometimes content is nil
    Map.get(delta, "content", "")
  end
  # Handle OpenaiEx stream format - the library returns parsed JSON objects
  def extract_text_from_stream(%{data: %{"choices" => [%{"delta" => %{"content" => content}} | _]}}) when is_binary(content) do
    # OpenaiEx parsed format
    content
  end
  def extract_text_from_stream(%{data: %{"choices" => [%{"delta" => delta} | _]}}) do
    # OpenaiEx parsed format - sometimes content is nil
    Map.get(delta, "content", "")
  end
  def extract_text_from_stream(chunk) do
    # Debug logging for unmatched chunks
    IO.puts("🔍 Unmatched stream chunk: #{inspect(chunk)}")
    ""
  end

  # Private helper function to extract text from various response formats
  defp extract_text_from_response(%{"content" => content}) when is_list(content) do
    content
    |> Enum.find_value("", fn
      %{"type" => "text", "text" => text} -> text
      _ -> nil
    end)
  end

  defp extract_text_from_response(response) do
    inspect(response)
  end

  # ============================================================================
  # Prompt Management
  # ============================================================================

  @doc """
  Create a new AI prompt.
  """
  def create_prompt(attrs) do
    %Prompt{}
    |> Prompt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get a prompt by ID.
  """
  def get_prompt(id) do
    Repo.get(Prompt, id)
  end

  @doc """
  Get a prompt by ID with preloaded associations.
  """
  def get_prompt_with_creator(id) do
    Prompt
    |> where([p], p.id == ^id)
    |> preload(:created_by_user)
    |> Repo.one()
  end

  @doc """
  List all active prompts.
  """
  def list_prompts do
    Prompt
    |> where([p], p.is_active == true)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the total count of AI prompts.
  """
  def count_prompts do
    try do
      Repo.aggregate(Prompt, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Returns the total count of AI prompts with optional filtering.

  ## Options

    * `:is_active` - Filter by active status (true/false)
    * `:category` - Filter by category
  """
  def count_prompts(opts) do
    try do
      is_active = Keyword.get(opts, :is_active)
      category = Keyword.get(opts, :category)

      query = Prompt

      query = if is_active != nil do
        where(query, [p], p.is_active == ^is_active)
      else
        query
      end

      query = if category do
        where(query, [p], p.category == ^category)
      else
        query
      end

      Repo.aggregate(query, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  List prompts with pagination and optional filtering.
  """
  def list_prompts(page, per_page, opts \\ []) do
    category = Keyword.get(opts, :category)
    search = Keyword.get(opts, :search)

    query = from p in Prompt,
      order_by: [desc: p.inserted_at],
      preload: [:created_by_user]

    query = if category && category != "all" do
      where(query, [p], p.category == ^category)
    else
      query
    end

    query = if search && String.trim(search) != "" do
      search_term = "%#{String.trim(search)}%"
      where(query, [p], ilike(p.name, ^search_term) or ilike(p.description, ^search_term))
    else
      query
    end

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = ceil(total_count / per_page)

    prompts = query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      prompts: prompts,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc """
  Update a prompt.
  """
  def update_prompt(prompt, attrs) do
    prompt
    |> Prompt.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a prompt.
  """
  def delete_prompt(prompt) do
    Repo.delete(prompt)
  end

  @doc """
  List prompts by category.
  """
  def list_prompts_by_category(category) do
    Prompt
    |> where([p], p.category == ^category and p.is_active == true)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Get the default system prompt from the database.
  Falls back to the hardcoded default if no system prompts exist.
  """
  def get_default_system_prompt do
    case list_prompts_by_category("system") do
      [] -> @default_system_prompt
      [first_prompt | _] -> first_prompt.content
    end
  end

  @doc """
  List all active system prompts.
  """
  def list_system_prompts do
    list_prompts_by_category("system")
  end

  @doc """
  List all active prompts for chat interface.
  Includes error handling for when tables don't exist.
  """
  def list_prompts_for_chat do
    try do
      Prompt
      |> where([p], p.is_active == true)
      |> order_by([p], asc: p.name)
      |> Repo.all()
    rescue
      _ -> []
    end
  end

  # ============================================================================
  # Evaluation Management
  # ============================================================================

  @doc """
  Create a new AI evaluation.
  """
  def create_eval(attrs) do
    case %Eval{}
         |> Eval.changeset(attrs)
         |> Repo.insert() do
      {:ok, eval} ->
        # Broadcast to PubSub for realtime updates
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "ai_evals",
          {:eval_created, eval}
        )
        {:ok, eval}

      error ->
        error
    end
  end

  @doc """
  Get an evaluation by ID.
  """
  def get_eval(id) do
    Repo.get(Eval, id)
  end

  @doc """
  Get an evaluation by ID with preloaded associations.
  """
  def get_eval_with_creator(id) do
    Eval
    |> where([e], e.id == ^id)
    |> preload([:created_by_user, :eval_runs])
    |> Repo.one()
  end

  @doc """
  List all active evaluations.
  """
  def list_evals do
    Eval
    |> where([e], e.is_active == true)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the total count of AI evaluations.
  """
  def count_evals do
    try do
      Repo.aggregate(Eval, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Returns the total count of AI evaluations with optional filtering.

  ## Options

    * `:is_active` - Filter by active status (true/false)
  """
  def count_evals(opts) do
    try do
      is_active = Keyword.get(opts, :is_active)

      query = Eval

      query = if is_active != nil do
        where(query, [e], e.is_active == ^is_active)
      else
        query
      end

      Repo.aggregate(query, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  List evaluations with pagination and optional filtering.
  """
  def list_evals(page, per_page, opts \\ []) do
    search = Keyword.get(opts, :search)
    status = Keyword.get(opts, :status, "all")

    query = from e in Eval,
      order_by: [desc: e.inserted_at],
      preload: [:created_by_user]

    query = if search && String.trim(search) != "" do
      search_term = "%#{String.trim(search)}%"
      where(query, [e], ilike(e.name, ^search_term) or ilike(e.description, ^search_term))
    else
      query
    end

    query = case status do
      "active" -> where(query, [e], e.is_active == true)
      "inactive" -> where(query, [e], e.is_active == false)
      _ -> query  # "all" or any other value shows all
    end

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = ceil(total_count / per_page)

    evals = query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      evals: evals,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc """
  Update an evaluation.
  """
  def update_eval(eval, attrs) do
    case eval
         |> Eval.changeset(attrs)
         |> Repo.update() do
      {:ok, updated_eval} ->
        # Broadcast to PubSub for realtime updates
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "ai_evals",
          {:eval_updated, updated_eval}
        )
        {:ok, updated_eval}

      error ->
        error
    end
  end

  @doc """
  Delete an evaluation.
  """
  def delete_eval(eval) do
    case Repo.delete(eval) do
      {:ok, deleted_eval} ->
        # Broadcast to PubSub for realtime updates
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "ai_evals",
          {:eval_deleted, deleted_eval}
        )
        {:ok, deleted_eval}

      error ->
        error
    end
  end

  # ============================================================================
  # Evaluation Run Management
  # ============================================================================

  @doc """
  Create a new evaluation run.
  """
  def create_eval_run(attrs) do
    %EvalRun{}
    |> EvalRun.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get an evaluation run by ID.
  """
  def get_eval_run(id) do
    EvalRun
    |> where([er], er.id == ^id)
    |> preload([:eval, :prompt, :run_by_user])
    |> Repo.one()
  end

  @doc """
  List evaluation runs for a specific evaluation.
  """
  def list_eval_runs(eval_id) do
    EvalRun
    |> where([er], er.eval_id == ^eval_id)
    |> order_by([er], desc: er.inserted_at)
    |> preload([:prompt, :run_by_user])
    |> Repo.all()
  end

  @doc """
  Returns the total count of evaluation runs.
  """
  def count_eval_runs do
    try do
      Repo.aggregate(EvalRun, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  Returns the total count of evaluation runs with optional filtering.

  ## Options

    * `:status` - Filter by status ("pending", "running", "completed", "failed")
    * `:eval_id` - Filter by specific evaluation
  """
  def count_eval_runs(opts) do
    try do
      status = Keyword.get(opts, :status)
      eval_id = Keyword.get(opts, :eval_id)

      query = EvalRun

      query = if status do
        where(query, [er], er.status == ^status)
      else
        query
      end

      query = if eval_id do
        where(query, [er], er.eval_id == ^eval_id)
      else
        query
      end

      Repo.aggregate(query, :count, :id)
    rescue
      _ -> 0
    end
  end

  @doc """
  List all evaluation runs with pagination and optional filtering.
  """
  def list_all_eval_runs(page, per_page, opts \\ []) do
    status = Keyword.get(opts, :status, "all")
    eval_id = Keyword.get(opts, :eval_id)
    prompt_id = Keyword.get(opts, :prompt_id)

    query = from er in EvalRun,
      order_by: [desc: er.inserted_at],
      preload: [:eval, :prompt, :run_by_user]

    query = case status do
      "completed" -> where(query, [er], er.status == "completed")
      "failed" -> where(query, [er], er.status == "failed")
      "running" -> where(query, [er], er.status == "running")
      "pending" -> where(query, [er], er.status == "pending")
      _ -> query  # "all" or any other value shows all
    end

    query = if eval_id do
      where(query, [er], er.eval_id == ^eval_id)
    else
      query
    end

    query = if prompt_id do
      where(query, [er], er.prompt_id == ^prompt_id)
    else
      query
    end

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = ceil(total_count / per_page)

    eval_runs = query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      eval_runs: eval_runs,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc """
  Delete an evaluation run.
  """
  def delete_eval_run(eval_run_id) do
    case get_eval_run(eval_run_id) do
      nil -> {:error, :eval_run_not_found}
      eval_run -> Repo.delete(eval_run)
    end
  end

  @doc """
  Run an evaluation against a specific model and optional prompt.
  Now uses the evaluation queue for rate limiting.
  """
  def run_evaluation(eval_id, model, user_id, prompt_id \\ nil, advanced_params \\ %{}) do
    with {:ok, _eval} <- get_eval_for_run(eval_id),
         {:ok, eval_run} <- create_eval_run(%{
           eval_id: eval_id,
           prompt_id: prompt_id,
           model: model,
           run_by: user_id,
           status: "pending",
           max_tokens: advanced_params[:max_tokens],
           max_tokens_active: advanced_params[:max_tokens_active] || false,
           temperature: advanced_params[:temperature],
           temperature_active: advanced_params[:temperature_active] || false,
           top_k: advanced_params[:top_k],
           top_k_active: advanced_params[:top_k_active] || false,
           top_p: advanced_params[:top_p],
           top_p_active: advanced_params[:top_p_active] || false
         }) do

      # Add to the evaluation queue instead of starting directly
      case Core.AI.EvaluationQueue.enqueue(eval_run.id) do
        {:ok, queue_position} ->
          require Logger
          Logger.info("📥 Evaluation #{eval_run.id} added to queue at position #{queue_position}")
          {:ok, eval_run}
        {:error, reason} ->
          require Logger
          Logger.error("❌ Failed to enqueue evaluation #{eval_run.id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp get_eval_for_run(eval_id) do
    case get_eval(eval_id) do
      nil -> {:error, :eval_not_found}
      eval -> {:ok, eval}
    end
  end

  # ============================================================================
  # Usage Tracking Functions
  # ============================================================================

  @doc """
  Logs AI usage with tracking information.
  """
  def log_usage(attrs) do
    Usage.log_usage(attrs)
  end

  @doc """
  Tracks a chat completion with performance metrics.
  """
  def track_chat_completion(model, action, user_id, conversation_id, message_id, start_time, result, opts \\ %{}) do
    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    {status, error_message, tokens} = case result do
      {:ok, response} ->
        # Extract token usage from response if available
        tokens = extract_token_usage(response)
        {"success", nil, tokens}

      {:error, error} ->
        {"error", format_error_message(error), %{}}
    end

    # Ensure we store the display name instead of API ID for consistency
    model_display_name = Models.get_display_name(model)

    attrs = %{
      model: model_display_name,
      action: action,
      status: status,
      user_id: user_id,
      conversation_id: conversation_id,
      message_id: message_id,
      response_time: response_time,
      error_message: error_message,
      prompt_tokens: tokens[:prompt_tokens],
      completion_tokens: tokens[:completion_tokens],
      total_tokens: tokens[:total_tokens],
      metadata: Map.merge(opts, %{
        advanced_params: extract_advanced_params(opts)
      })
    }

    log_usage(attrs)
  end

  @doc """
  Gets usage statistics for all models.
  """
  def get_usage_stats(opts \\ []) do
    Usage.get_all_models_stats(opts)
  end

  @doc """
  Gets usage statistics for a specific model.
  """
  def get_model_usage_stats(model, opts \\ []) do
    Usage.get_model_stats(model, opts)
  end

  @doc """
  Gets usage timeline data for visualization.
  """
  def get_usage_timeline(opts \\ []) do
    Usage.get_usage_timeline(opts)
  end

  @doc """
  Gets recent error logs for debugging.
  """
  def get_recent_errors(limit \\ 50) do
    Usage.get_recent_errors(limit)
  end

  @doc """
  Gets paginated and filtered error logs for debugging.

  ## Options
    * `:page` - Page number (default: 1)
    * `:per_page` - Items per page (default: 20)
    * `:model` - Filter by model (default: nil for all models)
    * `:status` - Filter by status (default: "error", can be "error", "timeout", or "all" for all statuses)
    * `:days` - Filter by time range in days (default: 30)

  ## Returns
    Map with keys: :errors, :page, :per_page, :total_count, :total_pages
  """
  def get_errors_paginated(opts \\ []) do
    Usage.get_errors_paginated(opts)
  end

  @doc """
  Gets usage statistics for all models with optional filtering.

  ## Options
    * `:days` - Filter by time range in days (default: 30)
    * `:status` - Filter by status (default: "all", can be "success", "error", "timeout", or "all")
    * `:model` - Filter by specific model (default: nil for all models)
  """
  def get_usage_stats_filtered(opts \\ []) do
    Usage.get_all_models_stats_filtered(opts)
  end

  @doc """
  Gets user-specific usage statistics.
  """
  def get_user_usage_stats(user_id, opts \\ []) do
    Usage.get_user_stats(user_id, opts)
  end

  # Private helper functions for usage tracking

  defp extract_token_usage(response) do
    case response do
      %{usage: %{input_tokens: prompt, output_tokens: completion}} ->
        %{
          prompt_tokens: prompt,
          completion_tokens: completion,
          total_tokens: prompt + completion
        }
      %{"usage" => %{"input_tokens" => prompt, "output_tokens" => completion}} ->
        %{
          prompt_tokens: prompt,
          completion_tokens: completion,
          total_tokens: prompt + completion
        }
      _ ->
        %{prompt_tokens: nil, completion_tokens: nil, total_tokens: nil}
    end
  end

  defp format_error_message(error) do
    case error do
      %{message: message} -> message
      %{"message" => message} -> message
      binary when is_binary(binary) -> binary
      _ -> inspect(error)
    end
  end

  defp extract_advanced_params(opts) do
    opts
    |> Map.take([:max_tokens, :temperature, :top_k, :top_p, :max_tokens_active, :temperature_active, :top_k_active, :top_p_active])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

end
