defmodule Ytdarr.Downloads.Tracker do
  use GenServer

  @moduledoc """
  Tracks ephemeral progress metadata for active video downloads.

  This GenServer keeps an in-memory map of active download progress keyed by
  `{job_id, video_id}`. The data exists only to support real-time UI updates
  while a download is running and is never persisted to the database. If the
  application restarts, all tracked progress is lost and active downloads must
  report progress again to repopulate the tracker.

  The tracker complements the persistent download lifecycle state stored on
  videos. `Ytdarr.ObanWorkers.VideoDownloader` owns the actual download work and
  can call this module to mark a download as started, push progress updates, and
  remove the entry when the job completes. Consumers such as LiveViews subscribe
  to the `"downloads"` PubSub topic through `Ytdarr.Downloads.subscribe/0` and
  receive throttled progress broadcasts emitted through
  `Ytdarr.Downloads.broadcast/1`.

  Progress updates are broadcast in the format:

      {:download_progress, job_id, video_id, %{pct: pct, speed: speed, eta: eta}}

  Broadcasts are throttled to at most once per second per tracked download so
  the UI can stay responsive without receiving a PubSub event for every
  low-level downloader output update.
  """

  @throttle_seconds 1

  @type job_id :: term()
  @type video_id :: term()
  @type progress :: %{
          pct: float() | nil,
          speed: String.t() | nil,
          eta: String.t() | nil,
          started_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type progress_update :: %{
          required(:pct) => float() | nil,
          required(:speed) => String.t() | nil,
          required(:eta) => String.t() | nil
        }

  @doc """
  Starts the download tracker GenServer.

  The server is registered under `#{inspect(__MODULE__)}` so callers can use the
  public API without passing a PID.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Registers a new active download for the given job and video.

  Any existing tracked entry for the same `{job_id, video_id}` pair is replaced
  with a fresh progress record.
  """
  @spec track_start(job_id(), video_id()) :: :ok
  def track_start(job_id, video_id) do
    GenServer.cast(__MODULE__, {:track_start, job_id, video_id})
  end

  @doc """
  Updates progress data for an active download.

  The in-memory state is always updated immediately. A
  `{:download_progress, job_id, video_id, progress}` PubSub event is broadcast
  through `Ytdarr.Downloads.broadcast/1` only when at least one second has
  passed since the last broadcast for that tracked entry.
  """
  @spec update_progress(job_id(), video_id(), progress_update()) :: :ok
  def update_progress(job_id, video_id, %{pct: _pct, speed: _speed, eta: _eta} = progress) do
    GenServer.cast(__MODULE__, {:update_progress, job_id, video_id, progress})
  end

  @doc """
  Stops tracking an active download.

  This removes the in-memory entry for the given `{job_id, video_id}` pair.
  """
  @spec track_complete(job_id(), video_id()) :: :ok
  def track_complete(job_id, video_id) do
    GenServer.cast(__MODULE__, {:track_complete, job_id, video_id})
  end

  @doc """
  Returns the most recently updated progress state for the given video.

  If the same video is being tracked under multiple job IDs, the newest entry by
  `updated_at` is returned. Returns `nil` when the video is not currently being
  tracked.
  """
  @spec get_progress(video_id()) :: progress() | nil
  def get_progress(video_id) do
    GenServer.call(__MODULE__, {:get_progress, video_id})
  end

  @doc """
  Lists all currently tracked downloads.

  Returns a list of `{video_id, progress_map}` tuples for every active tracked
  entry.
  """
  @spec list_active() :: [{video_id(), progress()}]
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:track_start, job_id, video_id}, state) do
    now = DateTime.utc_now()

    progress = %{
      pct: nil,
      speed: nil,
      eta: nil,
      started_at: now,
      updated_at: now,
      last_broadcast_at: nil
    }

    {:noreply, Map.put(state, {job_id, video_id}, progress)}
  end

  def handle_cast({:update_progress, job_id, video_id, attrs}, state) do
    now = DateTime.utc_now()
    key = {job_id, video_id}
    existing = Map.get(state, key, new_progress(now))

    progress = %{
      existing
      | pct: Map.get(attrs, :pct),
        speed: Map.get(attrs, :speed),
        eta: Map.get(attrs, :eta),
        updated_at: now
    }

    progress =
      if should_broadcast?(existing, now) do
        broadcast_progress(job_id, video_id, progress)
        Map.put(progress, :last_broadcast_at, now)
      else
        progress
      end

    {:noreply, Map.put(state, key, progress)}
  end

  def handle_cast({:track_complete, job_id, video_id}, state) do
    {:noreply, Map.delete(state, {job_id, video_id})}
  end

  @impl true
  def handle_call({:get_progress, video_id}, _from, state) do
    progress =
      state
      |> Enum.reduce(nil, fn
        {{_job_id, ^video_id}, progress}, nil ->
          progress

        {{_job_id, ^video_id}, progress}, current ->
          case DateTime.compare(progress.updated_at, current.updated_at) do
            :gt -> progress
            _ -> current
          end

        _, current ->
          current
      end)
      |> public_progress()

    {:reply, progress, state}
  end

  def handle_call(:list_active, _from, state) do
    active =
      Enum.map(state, fn {{_job_id, video_id}, progress} ->
        {video_id, public_progress(progress)}
      end)

    {:reply, active, state}
  end

  defp new_progress(now) do
    %{
      pct: nil,
      speed: nil,
      eta: nil,
      started_at: now,
      updated_at: now,
      last_broadcast_at: nil
    }
  end

  defp should_broadcast?(%{last_broadcast_at: nil}, _now), do: true

  defp should_broadcast?(%{last_broadcast_at: last_broadcast_at}, now) do
    DateTime.diff(now, last_broadcast_at, :second) >= @throttle_seconds
  end

  defp broadcast_progress(job_id, video_id, progress) do
    Ytdarr.Downloads.broadcast({:download_progress, job_id, video_id, progress_payload(progress)})
  end

  defp progress_payload(progress) do
    %{pct: progress.pct, speed: progress.speed, eta: progress.eta}
  end

  defp public_progress(nil), do: nil

  defp public_progress(progress) do
    Map.take(progress, [:pct, :speed, :eta, :started_at, :updated_at])
  end
end
