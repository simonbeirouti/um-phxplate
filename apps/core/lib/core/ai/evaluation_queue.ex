defmodule Core.AI.EvaluationQueue do
  @moduledoc """
  GenServer-based queue system for managing AI evaluation runs with rate limiting.

  This module implements a FIFO queue with configurable rate limiting to prevent
  overwhelming the Anthropic API. It manages evaluation runs by:

  1. Queuing evaluation requests
  2. Processing them one at a time with rate limiting
  3. Implementing cooldown periods between evaluations
  4. Providing status monitoring and queue management

  ## Configuration

  - `cooldown_ms`: Time to wait between evaluations (default: 5000ms)
  - `max_retries`: Maximum retry attempts for failed evaluations (default: 3)
  - `retry_delay_ms`: Delay between retry attempts (default: 10000ms)
  """

  use GenServer
  require Logger

  alias Core.Evaluations
  alias Core.AI.EvalRun
  alias Core.Repo

  # Default configuration
  @default_cooldown_ms 5_000      # 5 seconds between evaluations
  @default_max_retries 3          # Maximum retry attempts
  @default_retry_delay_ms 10_000  # 10 seconds between retries

  # State structure
  defstruct [
    :queue,           # :queue.queue() - FIFO queue of eval_run_ids
    :current,         # Current evaluation being processed
    :cooldown_ms,     # Cooldown period between evaluations
    :max_retries,     # Maximum retry attempts
    :retry_delay_ms,  # Delay between retries
    :stats            # Queue statistics
  ]

  ## Public API

  @doc """
  Start the evaluation queue GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add an evaluation run to the queue.
  """
  def enqueue(eval_run_id) when is_integer(eval_run_id) do
    GenServer.call(__MODULE__, {:enqueue, eval_run_id})
  end

  @doc """
  Get the current queue status and statistics.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Get the current queue size.
  """
  def queue_size do
    GenServer.call(__MODULE__, :queue_size)
  end

  @doc """
  Clear all pending evaluations from the queue.
  """
  def clear_queue do
    GenServer.call(__MODULE__, :clear_queue)
  end

  @doc """
  Update queue configuration.
  """
  def update_config(opts) do
    GenServer.call(__MODULE__, {:update_config, opts})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    Logger.info("🚀 Starting AI Evaluation Queue")

    state = %__MODULE__{
      queue: :queue.new(),
      current: nil,
      cooldown_ms: Keyword.get(opts, :cooldown_ms, @default_cooldown_ms),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms),
      stats: %{
        total_processed: 0,
        successful: 0,
        failed: 0,
        retries: 0,
        started_at: DateTime.utc_now()
      }
    }

    Logger.info("⚙️ Queue configuration: cooldown=#{state.cooldown_ms}ms, max_retries=#{state.max_retries}")

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, eval_run_id}, _from, state) do
    Logger.info("📥 Enqueueing evaluation run #{eval_run_id}")

    new_queue = :queue.in(eval_run_id, state.queue)
    new_state = %{state | queue: new_queue}

    # Start processing if not already running
    new_state = maybe_start_processing(new_state)

    queue_size = :queue.len(new_state.queue)
    Logger.info("📊 Queue size: #{queue_size}, Current: #{inspect(new_state.current)}")

    # Broadcast queue update
    broadcast_queue_update(new_state)

    {:reply, {:ok, queue_size}, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      queue_size: :queue.len(state.queue),
      current_evaluation: state.current,
      configuration: %{
        cooldown_ms: state.cooldown_ms,
        max_retries: state.max_retries,
        retry_delay_ms: state.retry_delay_ms
      },
      statistics: state.stats
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:queue_size, _from, state) do
    {:reply, :queue.len(state.queue), state}
  end

  @impl true
  def handle_call(:clear_queue, _from, state) do
    Logger.warning("🗑️ Clearing evaluation queue")
    new_state = %{state | queue: :queue.new()}
    broadcast_queue_update(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_config, opts}, _from, state) do
    new_state = %{state |
      cooldown_ms: Keyword.get(opts, :cooldown_ms, state.cooldown_ms),
      max_retries: Keyword.get(opts, :max_retries, state.max_retries),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, state.retry_delay_ms)
    }

    Logger.info("⚙️ Updated queue configuration: #{inspect(opts)}")
    broadcast_queue_update(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_max_retries, _from, state) do
    {:reply, state.max_retries, state}
  end

  @impl true
  def handle_call(:get_retry_delay, _from, state) do
    {:reply, state.retry_delay_ms, state}
  end

  @impl true
  def handle_info(:process_next, state) do
    new_state = process_next_evaluation(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:evaluation_completed, eval_run_id, result}, state) do
    Logger.info("✅ Evaluation #{eval_run_id} completed with result: #{inspect(result)}")

    # Update statistics
    new_stats = case result do
      :success ->
        %{state.stats |
          total_processed: state.stats.total_processed + 1,
          successful: state.stats.successful + 1
        }
      :failure ->
        %{state.stats |
          total_processed: state.stats.total_processed + 1,
          failed: state.stats.failed + 1
        }
    end

    new_state = %{state | current: nil, stats: new_stats}

    # Broadcast queue update
    broadcast_queue_update(new_state)

    # Schedule cooldown before processing next
    Logger.info("😴 Starting cooldown period (#{state.cooldown_ms}ms)")
    Process.send_after(self(), :process_next, state.cooldown_ms)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:retry_evaluation, eval_run_id, attempt}, state) do
    Logger.info("🔄 Retrying evaluation #{eval_run_id} (attempt #{attempt}/#{state.max_retries})")

    new_stats = %{state.stats | retries: state.stats.retries + 1}
    new_state = %{state | stats: new_stats}

    # Start the evaluation
    start_evaluation(eval_run_id, attempt)

    {:noreply, new_state}
  end

  ## Private Functions

  defp maybe_start_processing(%{current: nil} = state) do
    send(self(), :process_next)
    state
  end

  defp maybe_start_processing(state), do: state

  defp process_next_evaluation(%{current: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, eval_run_id}, new_queue} ->
        Logger.info("🔄 Processing evaluation #{eval_run_id}")

        new_state = %{state |
          queue: new_queue,
          current: %{eval_run_id: eval_run_id, attempt: 1, started_at: DateTime.utc_now()}
        }

        # Broadcast queue update
        broadcast_queue_update(new_state)

        # Start the evaluation
        start_evaluation(eval_run_id, 1)

        new_state

      {:empty, _queue} ->
        Logger.info("📭 Queue is empty, waiting for new evaluations")
        state
    end
  end

  defp process_next_evaluation(state) do
    Logger.debug("⏳ Evaluation already in progress, skipping")
    state
  end

  defp start_evaluation(eval_run_id, attempt) do
    Logger.info("🚀 Starting evaluation #{eval_run_id} (attempt #{attempt})")

    # Start the evaluation in a spawned process to avoid blocking the GenServer
    spawn(fn ->
      try do
        case Evaluations.run_model_based_eval(eval_run_id) do
          {:ok, _eval_run} ->
            send(__MODULE__, {:evaluation_completed, eval_run_id, :success})
          {:error, reason} ->
            Logger.error("❌ Evaluation #{eval_run_id} failed: #{inspect(reason)}")
            handle_evaluation_failure(eval_run_id, attempt, reason)
        end
      rescue
        error ->
          Logger.error("💥 Evaluation #{eval_run_id} crashed: #{inspect(error)}")
          handle_evaluation_failure(eval_run_id, attempt, error)
      end
    end)
  end

  defp handle_evaluation_failure(eval_run_id, attempt, reason) do
    max_retries = GenServer.call(__MODULE__, :get_max_retries)

    if attempt < max_retries do
      Logger.warning("⚠️ Evaluation #{eval_run_id} failed (attempt #{attempt}), scheduling retry")
      retry_delay = GenServer.call(__MODULE__, :get_retry_delay)
      Process.send_after(__MODULE__, {:retry_evaluation, eval_run_id, attempt + 1}, retry_delay)
    else
      Logger.error("💀 Evaluation #{eval_run_id} failed permanently after #{attempt} attempts")

      # Mark the evaluation as failed in the database
      case Repo.get(EvalRun, eval_run_id) do
        nil ->
          Logger.error("❌ Could not find eval run #{eval_run_id} to mark as failed")
        eval_run ->
          case eval_run
               |> EvalRun.fail_changeset("Failed after #{attempt} attempts: #{inspect(reason)}")
               |> Repo.update() do
            {:ok, _} ->
              Logger.info("✅ Marked eval run #{eval_run_id} as failed")
            {:error, changeset_error} ->
              Logger.error("❌ Could not mark eval run as failed: #{inspect(changeset_error)}")
          end
      end

      send(__MODULE__, {:evaluation_completed, eval_run_id, :failure})
    end
  end

  defp broadcast_queue_update(state) do
    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "evaluation_queue",
      {:queue_updated, %{
        queue_size: :queue.len(state.queue),
        current_evaluation: state.current,
        statistics: state.stats
      }}
    )
  end
end
