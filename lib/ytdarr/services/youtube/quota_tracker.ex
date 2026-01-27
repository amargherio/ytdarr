defmodule Ytdarr.Services.YouTube.QuotaTracker do
  @moduledoc """
  Tracks YouTube API quota usage to prevent exceeding daily limits.

  YouTube Data API v3 has a default daily quota of 10,000 units per Google Cloud
  project, which resets at midnight Pacific Time (PT).

  ## Quota Costs

  | Operation Type | Cost (Units) |
  |----------------|--------------|
  | Read (videos.list, playlists.list, etc.) | 1 unit |
  | Write (playlists.insert, videos.update, etc.) | ~50 units |
  | Search (search.list) | 100 units |
  | Video Upload | 1,600 units |
  | Thumbnail Upload/Update | 50 units |

  ## Usage

      # Record API usage
      QuotaTracker.record_usage(:read)
      QuotaTracker.record_usage(:search)
      QuotaTracker.record_usage(:read, 5)  # 5 read operations

      # Check current usage
      QuotaTracker.get_usage()
      # => %{used: 150, limit: 10000, remaining: 9850, percentage: 1.5}

      # Check if we can afford an operation
      QuotaTracker.can_afford?(:search)
      # => true

  ## Persistence

  Usage is persisted to the database and survives restarts. The state resets
  daily at midnight Pacific Time.
  """

  use GenServer

  alias Ytdarr.Settings

  require Logger

  @default_daily_limit 10_000

  # Quota costs per operation type
  @quota_costs %{
    read: 1,
    search: 100,
    write: 50,
    upload: 1_600,
    thumbnail: 50
  }

  # Warning thresholds (percentage of daily limit)
  @warning_threshold 80
  @critical_threshold 95

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records API usage for the given operation type.

  ## Parameters
    - operation_type: One of :read, :search, :write, :upload, :thumbnail
    - count: Number of operations (default: 1)

  ## Returns
    - :ok on success
    - {:warning, message} if usage exceeds warning threshold
    - {:critical, message} if usage exceeds critical threshold
  """
  def record_usage(operation_type, count \\ 1) when is_atom(operation_type) do
    GenServer.call(__MODULE__, {:record_usage, operation_type, count})
  end

  @doc """
  Gets the current quota usage statistics.

  ## Returns
    %{
      used: integer(),
      limit: integer(),
      remaining: integer(),
      percentage: float(),
      reset_at: DateTime.t()
    }
  """
  def get_usage do
    GenServer.call(__MODULE__, :get_usage)
  end

  @doc """
  Checks if we can afford the given operation type.

  ## Parameters
    - operation_type: One of :read, :search, :write, :upload, :thumbnail
    - count: Number of operations to check (default: 1)

  ## Returns
    - true if we have enough quota
    - false if the operation would exceed the daily limit
  """
  def can_afford?(operation_type, count \\ 1) when is_atom(operation_type) do
    GenServer.call(__MODULE__, {:can_afford?, operation_type, count})
  end

  @doc """
  Gets the quota cost for an operation type.
  """
  def get_cost(operation_type) do
    Map.get(@quota_costs, operation_type, 1)
  end

  @doc """
  Estimates the quota cost for a batch operation.

  ## Examples

      # Estimate cost for syncing 10 channels
      estimate_batch_cost(:channel_sync, 10)
      # => 24 (2 batched channel calls + 2 batched playlist calls + ~20 video batches)
  """
  def estimate_batch_cost(operation, count) do
    case operation do
      :channel_sync ->
        # Per channel: 1 channel call (batched) + 1 playlist call + N video batch calls
        # Assuming average of 2 video batches per channel
        channel_batches = ceil(count / 50)
        playlist_calls = count
        video_batches = count * 2
        channel_batches + playlist_calls + video_batches

      :playlist_sync ->
        # Per playlist: 1 playlistItems call per page + 1 videos call per 50 videos
        # Assuming average of 100 videos per playlist
        playlist_pages = count * 2
        video_batches = count * 2
        playlist_pages + video_batches

      :search ->
        count * @quota_costs[:search]

      _ ->
        count * @quota_costs[:read]
    end
  end

  @doc """
  Forces a reset of the quota counter (for testing or manual reset).
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Load persisted usage from database
    {used, reset_date} = load_persisted_usage()

    # Check if we need to reset (new day in PT timezone)
    current_date = current_pt_date()

    used =
      if reset_date != current_date do
        # New day, reset counter
        Logger.info("[QuotaTracker] New day detected, resetting quota counter")
        persist_usage(0, current_date)
        0
      else
        used
      end

    # Schedule daily reset check
    schedule_reset_check()

    state = %{
      used: used,
      limit: get_daily_limit(),
      reset_date: current_date
    }

    Logger.info("[QuotaTracker] Started with #{state.used}/#{state.limit} units used")

    {:ok, state}
  end

  @impl true
  def handle_call({:record_usage, operation_type, count}, _from, state) do
    cost = Map.get(@quota_costs, operation_type, 1) * count
    new_used = state.used + cost

    # Persist to database
    persist_usage(new_used, state.reset_date)

    # Check thresholds
    percentage = new_used / state.limit * 100

    result =
      cond do
        percentage >= @critical_threshold ->
          Logger.warning(
            "[QuotaTracker] CRITICAL: Quota at #{Float.round(percentage, 1)}% (#{new_used}/#{state.limit})"
          )

          {:critical, "Quota usage critical: #{Float.round(percentage, 1)}%"}

        percentage >= @warning_threshold ->
          Logger.warning(
            "[QuotaTracker] WARNING: Quota at #{Float.round(percentage, 1)}% (#{new_used}/#{state.limit})"
          )

          {:warning, "Quota usage high: #{Float.round(percentage, 1)}%"}

        true ->
          :ok
      end

    {:reply, result, %{state | used: new_used}}
  end

  @impl true
  def handle_call(:get_usage, _from, state) do
    remaining = max(0, state.limit - state.used)
    percentage = state.used / state.limit * 100

    result = %{
      used: state.used,
      limit: state.limit,
      remaining: remaining,
      percentage: Float.round(percentage, 2),
      reset_at: next_reset_time()
    }

    {:reply, result, state}
  end

  @impl true
  def handle_call({:can_afford?, operation_type, count}, _from, state) do
    cost = Map.get(@quota_costs, operation_type, 1) * count
    can_afford = state.used + cost <= state.limit

    {:reply, can_afford, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    current_date = current_pt_date()
    persist_usage(0, current_date)

    Logger.info("[QuotaTracker] Quota counter manually reset")

    {:reply, :ok, %{state | used: 0, reset_date: current_date}}
  end

  @impl true
  def handle_info(:check_reset, state) do
    current_date = current_pt_date()

    new_state =
      if current_date != state.reset_date do
        Logger.info("[QuotaTracker] Daily reset triggered")
        persist_usage(0, current_date)
        %{state | used: 0, reset_date: current_date, limit: get_daily_limit()}
      else
        state
      end

    schedule_reset_check()
    {:noreply, new_state}
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp schedule_reset_check do
    # Check every hour for day rollover
    Process.send_after(self(), :check_reset, :timer.hours(1))
  end

  defp current_pt_date do
    # Get current time in Pacific timezone
    # Using a simplified approach - PT is UTC-8 (PST) or UTC-7 (PDT)
    # For quota purposes, using UTC-8 is conservative
    utc_now = DateTime.utc_now()
    pt_offset_hours = -8

    utc_now
    |> DateTime.add(pt_offset_hours * 3600, :second)
    |> DateTime.to_date()
  end

  defp next_reset_time do
    # Next midnight PT
    current_date = current_pt_date()
    next_date = Date.add(current_date, 1)

    # Midnight PT is 8:00 UTC (during PST)
    DateTime.new!(next_date, ~T[08:00:00], "Etc/UTC")
  end

  defp get_daily_limit do
    # Allow configuring via settings
    case Settings.get_setting_value("youtube.daily_quota_limit") do
      nil -> @default_daily_limit
      limit when is_integer(limit) -> limit
      limit when is_binary(limit) -> String.to_integer(limit)
    end
  end

  defp load_persisted_usage do
    # Load from settings/database
    used =
      case Settings.get_setting_value("youtube.quota_used_today") do
        nil -> 0
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    reset_date =
      case Settings.get_setting_value("youtube.quota_reset_date") do
        nil ->
          current_pt_date()

        date_string when is_binary(date_string) ->
          case Date.from_iso8601(date_string) do
            {:ok, date} -> date
            _ -> current_pt_date()
          end
      end

    {used, reset_date}
  end

  defp persist_usage(used, reset_date) do
    # Persist to settings
    Settings.put_setting("youtube.quota_used_today", used, "integer")
    Settings.put_setting("youtube.quota_reset_date", Date.to_iso8601(reset_date), "string")
  rescue
    e ->
      Logger.error("[QuotaTracker] Failed to persist usage: #{inspect(e)}")
  end
end
