defmodule YtdarrWeb.QueueLive do
  @moduledoc """
  LiveView page for the download queue, showing active and pending downloads.

  Active downloads show real-time progress bars (percentage, speed, ETA) when
  the `DownloadTracker` has data. Pending downloads are listed with their
  approximate queue position based on Oban's fetch order.

  ## Real-time updates

  The page subscribes to the `"downloads"` PubSub topic for immediate updates
  when downloads start, progress, complete, or fail. A 5-second poll timer
  acts as a fallback to reconcile state if PubSub events are missed.

  Progress-specific events (`{:download_progress, ...}`) only update the
  progress map without re-querying the database, for efficiency.
  """
  use YtdarrWeb, :live_view

  alias Ytdarr.Downloads
  alias Ytdarr.Downloads.Tracker

  @poll_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Downloads.subscribe()
      :timer.send_interval(@poll_interval_ms, self(), :poll)
    end

    {:ok,
     socket
     |> assign(:page_title, "Queue")
     |> assign(:progress, %{})
     |> load_queue()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_queue(socket)}
  end

  @impl true
  def handle_info({:download_progress, _job_id, video_id, progress_data}, socket) do
    # Only update the progress map — no database round-trip needed
    progress = Map.put(socket.assigns.progress, video_id, progress_data)
    {:noreply, assign(socket, :progress, progress)}
  end

  def handle_info(:poll, socket) do
    {:noreply, load_queue(socket)}
  end

  def handle_info({event, _job_id, _video_id, _meta}, socket)
      when event in [:download_started, :download_failed] do
    {:noreply, load_queue(socket)}
  end

  def handle_info({event, _job_id, _video_id}, socket)
      when event in [:download_completed] do
    {:noreply, load_queue(socket)}
  end

  def handle_info({:download_queued, _video_id, _meta}, socket) do
    {:noreply, load_queue(socket)}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:queue}>
      <.header>
        Download queue
        <:subtitle>Monitor active downloads, pending jobs, and worker slot usage.</:subtitle>
        <:actions>
          <.button id="queue-refresh" phx-click="refresh">
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </.button>
        </:actions>
      </.header>

      <section id="queue-summary" class="grid gap-4 md:grid-cols-3">
        <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-sm font-medium text-base-content/70">Active downloads</p>
              <p class="mt-2 text-3xl font-semibold text-base-content">{@status.active}</p>
            </div>
            <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/10 text-primary">
              <.icon name="hero-arrow-down-tray" class="size-5" />
            </div>
          </div>
          <p class="mt-3 text-sm text-base-content/60">Jobs currently consuming download workers.</p>
        </div>

        <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-sm font-medium text-base-content/70">Pending jobs</p>
              <p class="mt-2 text-3xl font-semibold text-base-content">{@status.pending}</p>
            </div>
            <div class="flex size-11 items-center justify-center rounded-2xl bg-secondary/10 text-secondary">
              <.icon name="hero-clock" class="size-5" />
            </div>
          </div>
          <p class="mt-3 text-sm text-base-content/60">
            Queued items waiting for the next open slot.
          </p>
        </div>

        <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-sm font-medium text-base-content/70">Worker slots</p>
              <p class="mt-2 text-3xl font-semibold text-base-content">
                {@status.active} / {format_count(@status.concurrency)}
              </p>
            </div>
            <div class="flex size-11 items-center justify-center rounded-2xl bg-accent/10 text-accent">
              <.icon name="hero-server-stack" class="size-5" />
            </div>
          </div>
          <p class="mt-3 text-sm text-base-content/60">
            Configured concurrency for the video downloader queue.
          </p>
        </div>
      </section>

      <section class="grid gap-6 xl:grid-cols-[1.15fr,0.85fr]">
        <div
          id="queue-active"
          class="overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="flex items-center justify-between gap-4 border-b border-base-300 px-5 py-4">
            <div>
              <h2 class="text-base font-semibold text-base-content">Active downloads</h2>
              <p class="text-sm text-base-content/65">Live jobs currently being processed.</p>
            </div>
            <span class="badge badge-primary badge-soft">{length(@active_downloads)}</span>
          </div>

          <div
            :if={@active_downloads == []}
            id="queue-active-empty"
            class="px-5 py-8 text-sm text-base-content/60"
          >
            No downloads are running right now.
          </div>

          <div :if={@active_downloads != []} class="divide-y divide-base-300">
            <div
              :for={download <- @active_downloads}
              id={"active-download-#{download.job_id}"}
              class="flex items-start gap-4 px-5 py-4"
            >
              <div class="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-base-200">
                <img
                  :if={download.thumbnail_url}
                  src={download.thumbnail_url}
                  alt={download.video_title}
                  class="h-full w-full object-cover"
                />
                <.icon
                  :if={!download.thumbnail_url}
                  name="hero-photo"
                  class="size-7 text-base-content/35"
                />
              </div>

              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="space-y-1">
                    <p class="truncate font-semibold text-base-content">{download.video_title}</p>
                    <p class="text-sm text-base-content/65">{download.channel_name}</p>
                  </div>
                  <span class="badge badge-success badge-soft">Running</span>
                </div>

                <.download_progress_bar
                  pct={get_in(@progress, [download.video_id, :pct])}
                  speed={get_in(@progress, [download.video_id, :speed])}
                  eta={get_in(@progress, [download.video_id, :eta])}
                  class="mt-3"
                />

                <div class="mt-2 flex flex-wrap gap-x-5 gap-y-2 text-sm text-base-content/60">
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name="hero-play" class="size-4" />
                    Started {format_datetime(download.started_at)}
                  </span>
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name="hero-hashtag" class="size-4" /> Job #{download.job_id}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div
          id="queue-pending"
          class="overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="flex items-center justify-between gap-4 border-b border-base-300 px-5 py-4">
            <div>
              <h2 class="text-base font-semibold text-base-content">Queued next</h2>
              <p class="text-sm text-base-content/65">Jobs waiting for a downloader worker.</p>
            </div>
            <span class="badge badge-secondary badge-soft">{length(@pending_downloads)}</span>
          </div>

          <div
            :if={@pending_downloads == []}
            id="queue-pending-empty"
            class="px-5 py-8 text-sm text-base-content/60"
          >
            The queue is clear.
          </div>

          <div :if={@pending_downloads != []} class="divide-y divide-base-300">
            <%= for {download, position} <- Enum.with_index(@pending_downloads, 1) do %>
              <div
                id={"pending-download-#{download.job_id}"}
                class="flex items-start gap-4 px-5 py-4"
              >
                <div class="flex size-10 shrink-0 items-center justify-center rounded-2xl bg-base-200 text-sm font-semibold text-base-content/70">
                  {position}
                </div>

                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="space-y-1">
                      <p class="truncate font-semibold text-base-content">{download.video_title}</p>
                      <p class="text-sm text-base-content/65">{download.channel_name}</p>
                    </div>
                    <span class={["badge badge-soft", queue_badge_class(download.state)]}>
                      {queue_state_label(download.state)}
                    </span>
                  </div>

                  <div class="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-sm text-base-content/60">
                    <span class="inline-flex items-center gap-1.5">
                      <.icon name="hero-clock" class="size-4" />
                      Scheduled {format_datetime(download.scheduled_at)}
                    </span>
                    <span class="inline-flex items-center gap-1.5">
                      <.icon name="hero-hashtag" class="size-4" /> Job #{download.job_id}
                    </span>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_queue(socket) do
    # Merge ephemeral progress data from the in-memory tracker
    tracker_progress =
      Tracker.list_active()
      |> Map.new(fn {video_id, progress} ->
        {video_id, Map.take(progress, [:pct, :speed, :eta])}
      end)

    progress = Map.merge(socket.assigns.progress, tracker_progress)

    socket
    |> assign(:status, Downloads.queue_status())
    |> assign(:active_downloads, Downloads.list_active_downloads())
    |> assign(:pending_downloads, Downloads.list_pending_downloads())
    |> assign(:progress, progress)
  end

  defp format_count(nil), do: "—"
  defp format_count(value), do: value

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp format_datetime(_), do: "—"

  defp queue_badge_class("available"), do: "badge-neutral"
  defp queue_badge_class("scheduled"), do: "badge-info"
  defp queue_badge_class("retryable"), do: "badge-warning"
  defp queue_badge_class(_state), do: "badge-neutral"

  defp queue_state_label("available"), do: "Queued"
  defp queue_state_label("scheduled"), do: "Scheduled"
  defp queue_state_label("retryable"), do: "Retrying"
  defp queue_state_label(state) when is_binary(state), do: Phoenix.Naming.humanize(state)
  defp queue_state_label(_state), do: "Queued"
end
