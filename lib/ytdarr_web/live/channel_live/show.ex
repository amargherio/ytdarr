defmodule YtdarrWeb.ChannelLive.Show do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channels}>
      <%!-- Action toolbar (Sonarr-inspired) --%>
      <div class="flex flex-wrap items-center gap-2 px-2 py-2 -mx-6 -mt-4 mb-4 bg-base-200/50 border-b border-base-300">
        <div class="flex flex-wrap items-center gap-1.5 flex-1">
          <.button
            title="Refresh channel data"
            phx-click="refresh-channel-data"
            phx-value-id={@channel.id}
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </.button>
          <.button
            title="Edit channel"
            navigate={~p"/channels/#{@channel}/edit?return_to=show"}
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
          <.button
            title={"#{if @channel.is_monitored, do: "Unmonitor", else: "Monitor"} channel"}
            phx-click="toggle-monitor"
            phx-value-id={@channel.id}
            phx-value-type="channel"
            class={
              if(@channel.is_monitored,
                do: "btn btn-sm gap-1 btn-ghost",
                else: "btn btn-sm gap-1 btn-primary btn-soft"
              )
            }
          >
            <%= if @channel.is_monitored do %>
              <.icon name="hero-bookmark-solid" class="size-4" /> Monitored
            <% else %>
              <.icon name="hero-bookmark" class="size-4" /> Monitor
            <% end %>
          </.button>
          <.button
            title="Delete downloaded videos"
            phx-click="delete-channel-files"
            phx-value-id={@channel.id}
            class="btn btn-ghost btn-sm gap-1 text-error hover:bg-error/10"
          >
            <.icon name="hero-trash" class="size-4" /> Delete Files
          </.button>
        </div>
        <div class="flex items-center gap-1.5">
          <button
            title={if(@all_expanded?, do: "Collapse all", else: "Expand all")}
            phx-click="toggle-expand-all"
            class="btn btn-ghost btn-sm gap-1"
          >
            <%= if @all_expanded? do %>
              <.icon name="hero-chevron-double-up" class="size-4" /> Collapse All
            <% else %>
              <.icon name="hero-chevron-double-down" class="size-4" /> Expand All
            <% end %>
          </button>
        </div>
      </div>

      <%!-- Hero header with banner + channel info (Sonarr-style) --%>
      <.hero_header banner_url={~p"/images/channels/#{@channel.id}/banner"} mode="ratio" ratio="6/1">
        <div class="flex items-start gap-5">
          <img
            src={~p"/images/channels/#{@channel.id}/avatar"}
            alt={@channel.name}
            class="w-28 h-28 rounded-xl shadow-lg border-2 border-white/20 flex-shrink-0 hidden sm:block"
          />
          <div class="flex-1 min-w-0 space-y-2">
            <h1 class="text-3xl md:text-4xl font-bold truncate">{@channel.name}</h1>
            <%= if @channel.platform_username do %>
              <p class="text-sm text-white/70">{@channel.platform_username}</p>
            <% end %>
            <%= if @channel.description do %>
              <p class="text-sm text-white/60 line-clamp-2 max-w-2xl">{@channel.description}</p>
            <% end %>
            <div class="flex flex-wrap items-center gap-2 pt-1">
              <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-white/15 text-white/90">
                <.icon name="hero-play" class="size-3" /> {length(@videos)} videos
              </span>
              <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-white/15 text-white/90">
                <.icon name="hero-queue-list" class="size-3" /> {length(@playlists)} playlists
              </span>
              <%= if @channel.is_monitored do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-success/30 text-white">
                  <.icon name="hero-bookmark-solid" class="size-3" /> Monitored
                </span>
              <% end %>
            </div>
          </div>
        </div>
      </.hero_header>

      <%!-- Metadata pills --%>
      <div class="flex flex-wrap items-center gap-2">
        <%= if @channel.base_path do %>
          <.data_pill variant="info" size="sm">
            <.icon name="hero-folder-arrow-down" class="size-3.5" /> {@channel.base_path}
          </.data_pill>
        <% end %>
        <.data_pill variant={if(@channel.is_monitored, do: "success", else: "warning")} size="sm">
          <%= if @channel.is_monitored do %>
            <.icon name="hero-bookmark-solid" class="size-3.5" /> Monitored
          <% else %>
            <.icon name="hero-bookmark" class="size-3.5" /> Not Monitored
          <% end %>
        </.data_pill>
        <%= if @channel.is_monitored && @channel.is_monitored_since do %>
          <.data_pill variant="info" size="sm">
            <.icon name="hero-clock" class="size-3.5" />
            Since: {format_datetime(@channel.is_monitored_since)}
          </.data_pill>
        <% end %>
        <%= if @channel.last_checked_at do %>
          <.data_pill variant="info" size="sm">
            <.icon name="hero-clock" class="size-3.5" />
            Checked: {format_datetime(@channel.last_checked_at)}
          </.data_pill>
        <% end %>
        <.data_pill variant="secondary" size="sm" href={@channel.url}>
          <.icon name="hero-link" class="size-3.5" /> {@channel.platform_username || @channel.url}
        </.data_pill>
      </div>

      <%!-- All Videos section --%>
      <% all_downloaded = Enum.count(@videos, &(&1.download_state == :downloaded)) %>
      <div class="border border-base-300 bg-base-100 rounded-xl overflow-hidden">
        <div class="flex items-center gap-3 px-4 py-3">
          <.icon name="hero-film" class="size-5 text-base-content/50 flex-shrink-0" />
          <button
            phx-click="toggle-videos-expand"
            class="flex items-center gap-3 flex-1 min-w-0 cursor-pointer text-left"
          >
            <span class="font-medium">All Videos</span>
            <span class="badge badge-sm badge-ghost">{length(@videos)} videos</span>
          </button>
          <div class="flex items-center gap-2 flex-shrink-0">
            <span class="text-xs text-base-content/50">{all_downloaded}/{length(@videos)}</span>
            <button
              title="Delete all video files"
              phx-click="delete-video-files"
              class="btn btn-ghost btn-xs btn-square text-error/60 hover:text-error"
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
            <button
              phx-click="toggle-videos-expand"
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon
                name={if(@videos_expanded?, do: "hero-chevron-up", else: "hero-chevron-down")}
                class="size-4 transition-transform duration-200"
              />
            </button>
          </div>
        </div>
        <.progress_bar completed={all_downloaded} total={length(@videos)} class="mx-4" />
        <%= if @videos_expanded? do %>
          <div class="px-4 py-3 border-t border-base-200">
            <.video_table id="all-videos" videos={@videos} channel_id={@channel.id} />
          </div>
        <% end %>
      </div>

      <%!-- Playlists (Sonarr season pattern) --%>
      <%= for playlist <- @playlists do %>
        <% downloaded_count = Enum.count(playlist.videos, &(&1.download_state == :downloaded)) %>
        <% total_count = length(playlist.videos) %>
        <% expanded? = MapSet.member?(@expanded_playlists, playlist.id) %>
        <div class="border border-base-300 bg-base-100 rounded-xl overflow-hidden">
          <%!-- Playlist header --%>
          <div class="flex items-center gap-3 px-4 py-3">
            <button
              title={"#{if playlist.is_monitored, do: "Unmonitor", else: "Monitor"} playlist"}
              phx-click="toggle-monitor"
              phx-value-id={playlist.id}
              phx-value-type="playlist"
              class="btn btn-ghost btn-xs btn-square flex-shrink-0"
            >
              <%= if playlist.is_monitored do %>
                <.icon name="hero-bookmark-solid" class="size-4 text-success" />
              <% else %>
                <.icon name="hero-bookmark" class="size-4 text-base-content/40" />
              <% end %>
            </button>
            <button
              phx-click="toggle-playlist-expand"
              phx-value-id={to_string(playlist.id)}
              class="flex items-center gap-3 flex-1 min-w-0 cursor-pointer text-left"
            >
              <span class="font-medium truncate">{playlist.name}</span>
              <span class="badge badge-sm badge-ghost">{total_count} videos</span>
            </button>
            <div class="flex items-center gap-2 flex-shrink-0">
              <span class="text-xs text-base-content/50">{downloaded_count}/{total_count}</span>
              <button
                title="Delete playlist files"
                phx-click="delete-playlist-files"
                phx-value-id={playlist.external_id}
                class="btn btn-ghost btn-xs btn-square text-error/60 hover:text-error"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
              <button
                phx-click="toggle-playlist-expand"
                phx-value-id={to_string(playlist.id)}
                class="btn btn-ghost btn-xs btn-square"
              >
                <.icon
                  name={if(expanded?, do: "hero-chevron-up", else: "hero-chevron-down")}
                  class="size-4 transition-transform duration-200"
                />
              </button>
            </div>
          </div>
          <%!-- Progress bar --%>
          <.progress_bar completed={downloaded_count} total={total_count} class="mx-4" />
          <%!-- Expanded video table --%>
          <%= if expanded? do %>
            <div class="px-4 py-3 border-t border-base-200">
              <.video_table
                id={"videos-#{playlist.id}"}
                videos={playlist.videos}
                channel_id={@channel.id}
              />
            </div>
          <% end %>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    channel = Content.get_channel!(id, load: [:playlists, :videos])

    # Load videos for each playlist with videos in descending order by upload date
    playlists =
      Enum.map(channel.playlists, fn playlist ->
        Ash.get!(Content.Playlist, playlist.id, load: [:videos])
        |> sort_playlist_videos()
      end)

    playlist_ids = MapSet.new(playlists, & &1.id)

    {:ok,
     socket
     |> assign(:page_title, channel.name)
     |> assign(:channel, channel)
     |> assign(:playlists, playlists)
     |> assign(:videos, sort_videos(channel.videos))
     |> assign(:expanded_playlists, MapSet.new())
     |> assign(:all_expanded?, false)
     |> assign(:videos_expanded?, false)
     |> assign(:all_playlist_ids, playlist_ids)}
  end

  @impl true
  def handle_event("toggle-playlist-expand", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)

    expanded =
      if MapSet.member?(socket.assigns.expanded_playlists, id),
        do: MapSet.delete(socket.assigns.expanded_playlists, id),
        else: MapSet.put(socket.assigns.expanded_playlists, id)

    all_expanded? = MapSet.equal?(expanded, socket.assigns.all_playlist_ids)

    {:noreply,
     socket
     |> assign(:expanded_playlists, expanded)
     |> assign(:all_expanded?, all_expanded? && socket.assigns.videos_expanded?)}
  end

  @impl true
  def handle_event("toggle-videos-expand", _params, socket) do
    videos_expanded? = !socket.assigns.videos_expanded?

    all_expanded? =
      MapSet.equal?(socket.assigns.expanded_playlists, socket.assigns.all_playlist_ids) &&
        videos_expanded?

    {:noreply,
     socket
     |> assign(:videos_expanded?, videos_expanded?)
     |> assign(:all_expanded?, all_expanded?)}
  end

  @impl true
  def handle_event("toggle-expand-all", _params, socket) do
    expanding? = !socket.assigns.all_expanded?

    expanded_playlists =
      if expanding?,
        do: socket.assigns.all_playlist_ids,
        else: MapSet.new()

    {:noreply,
     socket
     |> assign(:expanded_playlists, expanded_playlists)
     |> assign(:videos_expanded?, expanding?)
     |> assign(:all_expanded?, expanding?)}
  end

  @impl true
  def handle_event("toggle-monitor", %{"id" => id, "type" => type}, socket) do
    case type do
      "channel" ->
        channel = Content.get_channel!(id)

        case Content.toggle_channel_monitor(channel) do
          {:ok, updated_channel} ->
            {:noreply,
             socket
             |> assign(:channel, updated_channel)
             |> put_flash(:info, "Channel status updated.")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to update channel status.")}
        end

      "playlist" ->
        playlist = Content.get_playlist!(id)

        case Content.toggle_playlist_monitor(playlist) do
          {:ok, updated_playlist} ->
            # Update the specific playlist in the list - need to reload with videos
            updated_playlist_with_videos =
              Content.get_playlist!(updated_playlist.id, load: [:videos])
              |> sort_playlist_videos()

            updated_playlists =
              Enum.map(socket.assigns.playlists, fn p ->
                if p.id == updated_playlist.id, do: updated_playlist_with_videos, else: p
              end)

            {:noreply,
             socket
             |> assign(:playlists, updated_playlists)
             |> put_flash(:info, "Playlist status updated.")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to update playlist status.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("queue-download", %{"id" => video_id, "channel-id" => channel_id}, socket) do
    Logger.info("Queue download for video #{video_id}")

    case Content.queue_video_download(video_id, channel_id) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> refresh_video_assigns()
         |> put_flash(:info, "Video queued for download.")}

      {:error, :video_blocklisted} ->
        {:noreply,
         socket
         |> refresh_video_assigns()
         |> put_flash(
           :error,
           "This video is blocklisted. Remove it from the blocklist before downloading."
         )}

      {:error, error} ->
        Logger.error("Failed to queue video #{video_id}: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Failed to queue video for download.")}
    end
  end

  @impl true
  def handle_event("blocklist-video", %{"id" => video_id}, socket) do
    with {:ok, video} <- Content.get_video(video_id),
         {:ok, _video} <- Content.blocklist_video(video) do
      {:noreply,
       socket
       |> refresh_video_assigns()
       |> put_flash(:info, "Video added to blocklist.")}
    else
      {:error, error} ->
        Logger.error("Failed to blocklist video #{video_id}: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Failed to add video to blocklist.")}
    end
  end

  @impl true
  def handle_event("unblocklist-video", %{"id" => video_id}, socket) do
    with {:ok, video} <- Content.get_video(video_id),
         {:ok, _video} <- Content.unblocklist_video(video) do
      {:noreply,
       socket
       |> refresh_video_assigns()
       |> put_flash(:info, "Video removed from blocklist.")}
    else
      {:error, error} ->
        Logger.error("Failed to unblock video #{video_id}: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Failed to remove video from blocklist.")}
    end
  end

  @impl true
  def handle_event("delete-video", %{"id" => video_id}, socket) do
    Logger.info("Delete video #{video_id}")
    Content.delete_video_file(video_id)

    {:noreply,
     socket
     |> refresh_video_assigns()
     |> put_flash(:info, "Video file deleted.")}
  end

  @impl true
  def handle_event("delete-channel-files", %{"id" => _channel_id}, socket) do
    # TODO: Implement channel file deletion
    {:noreply,
     socket
     |> put_flash(:info, "Channel file deletion not yet implemented.")}
  end

  @impl true
  def handle_event("delete-playlist-files", %{"id" => _playlist_id}, socket) do
    # TODO: Implement playlist file deletion
    {:noreply,
     socket
     |> put_flash(:info, "Playlist file deletion not yet implemented.")}
  end

  @impl true
  def handle_event("delete-video-files", _params, socket) do
    # TODO: Implement all video files deletion
    {:noreply,
     socket
     |> put_flash(:info, "Video file deletion not yet implemented.")}
  end

  @impl true
  def handle_event("refresh-channel-data", _params, socket) do
    Content.sync_content("channel", socket.assigns.channel.id)

    {:noreply,
     socket
     |> put_flash(:info, "Channel data refresh in progress.")}
  end

  defp sort_playlist_videos(playlist) do
    %{playlist | videos: sort_videos(playlist.videos)}
  end

  defp sort_videos(videos) do
    Enum.sort_by(videos, &(&1.upload_date || ~D[1970-01-01]), {:desc, Date})
  end

  defp refresh_video_assigns(socket) do
    channel = Content.get_channel!(socket.assigns.channel.id, load: [:playlists, :videos])

    playlists =
      Enum.map(channel.playlists, fn playlist ->
        Content.get_playlist!(playlist.id, load: [:videos])
        |> sort_playlist_videos()
      end)

    socket
    |> assign(:channel, channel)
    |> assign(:playlists, playlists)
    |> assign(:videos, sort_videos(channel.videos))
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_datetime(other), do: to_string(other)
end
