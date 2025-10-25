defmodule YtdarrWeb.ChannelLive.Show do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channels}>
      <.hero_header banner_url={@channel.banner_url}>
        <div class="left-06">
          <div class="flex flex-row flex-wrap justify-start gap-4">
            <image src={@channel.avatar_url} alt={@channel.name} class="w-24 h-24 rounded-full" />
            <h1 class="mb-5 text-5xl font-bold">{@channel.name}</h1>
            <p class="mb-5">{@channel.description}</p>
          </div>
        </div>
        <:actions>
          <div class="flex flex-col flex-wrap justify-center gap-2">
            <%!-- <.button navigate={~p"/channels"}>
              <.icon name="hero-arrow-left" />
            </.button> --%>
            <.button title="Edit channel" navigate={~p"/channels/#{@channel}/edit?return_to=show"}>
              <.icon name="hero-pencil-square" /> Edit channel
            </.button>
            <.button
              title={"#{if @channel.is_monitored, do: "Unmonitor", else: "Monitor"} channel"}
              phx-click="toggle-monitor"
              phx-value-id={@channel.id}
              phx-value-type="channel"
            >
              <%= if @channel.is_monitored do %>
                <.icon name="hero-bookmark-solid" /> Unmonitor channel
              <% else %>
                <.icon name="hero-bookmark" /> Monitor channel
              <% end %>
            </.button>
            <.button
              title="Refresh channel data"
              phx-click="refresh-channel-data"
              phx-value-id={@channel.id}
            >
              <.icon name="hero-arrow-path" /> Refresh channel data
            </.button>
            <.button
              title="Delete downloaded videos"
              phx-click="delete-channel-files"
              phx-value-id={@channel.id}
            >
              <.icon name="hero-trash" /> Delete downloaded videos
            </.button>
          </div>
        </:actions>
      </.hero_header>
      
    <!-- channel metadata -->
      <div class="flex flex-wrap justify-start gap-4">
        <div class="bg-slate-300 p-2 rounded">
          <.icon name="hero-folder-arrow-down" /> {@channel.base_path}
        </div>
        <div class="bg-slate-300 p-2 rounded">
          <%= if @channel.is_monitored do %>
            <.icon name="hero-bookmark-solid" /> Monitored
          <% else %>
            <.icon name="hero-bookmark" /> Not Monitored
          <% end %>
        </div>
        <div class="bg-slate-300 p-2 rounded">
          <.icon name="hero-clock" /> Last checked at: {@channel.last_checked_at}
        </div>
        <div class="bg-slate-300 p-2 rounded">
          <.icon name="hero-link" /> <a href={@channel.url}>{@channel.platform_username}</a>
        </div>
      </div>

      <%= for playlist <- @playlists do %>
        <div tabindex="0" class="collapse collapse-arrow bg-base-100 border-base-300 border">
          <div class="collapse-title text-xl font-medium after:start-5 after:end-auto pe-4 ps-12">
            {playlist.name}
            <div class="flex flex-wrap justify-center md:justify-end gap-2 md:min-w-[12rem]">
              <.button
                title={"#{if playlist.is_monitored, do: "Unmonitor", else: "Monitor"} playlist"}
                phx-click="toggle-playlist-monitor"
                phx-value-id={playlist.id}
                phx-value-type="playlist"
              >
                <%= if playlist.is_monitored do %>
                  <.icon name="hero-bookmark-solid" />
                <% else %>
                  <.icon name="hero-bookmark" />
                <% end %>
              </.button>
              <.button
                title="Delete playlist files"
                phx-click="delete-playlist-files"
                phx-value-id={playlist.id}
              >
                <.icon name="hero-trash" />
              </.button>
            </div>
          </div>
          <div class="collapse-content">
            <.table id={"videos-#{playlist.id}"} rows={playlist.videos}>
              <:col :let={video} label="Title">{video.title}</:col>
              <:col :let={video} label="Upload Date">{video.upload_date}</:col>
              <:col :let={video} label="Download Status">{video.is_downloaded}</:col>
            </.table>
          </div>
        </div>
      <% end %>

      <div tabindex="0" class="collapse collapse-arrow bg-base-100 border-base-300 border">
        <div class="collapse-title text-xl font-medium after:start-5 after:end-auto pe-4 ps-12">
          Videos
        </div>
        <div class="collapse-content">
          <.table id="videos" rows={@videos}>
            <:col :let={video} label="Title">{video.title}</:col>
            <:col :let={video} label="Upload Date">{video.upload_date}</:col>
            <:col :let={video} label="Download Status">{video.is_downloaded}</:col>
            <:col :let={video} label="Actions">
              <%= if video.is_downloaded do %>
                <.button
                  title="Delete downloaded video"
                  s
                  phx-click="delete-video"
                  phx-value-id={video.id}
                  class={["btn-sm"]}
                >
                  <.icon name="hero-trash" />
                </.button>
              <% else %>
                <.button
                  phx-click="queue-download"
                  phx-value-id={video.id}
                  class={["btn-sm"]}
                >
                  <.icon name="hero-arrow-down-tray" />
                </.button>
              <% end %>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    playlists =
      id
      |> Content.list_playlists_for_channel()
      |> Enum.map(fn playlist -> Content.get_playlist_with_videos(playlist.id) end)

    videos = Content.list_videos_for_channel(id)

    {:ok,
     socket
     |> assign(:page_title, "Show Channel")
     |> assign(:channel, Content.get_channel!(id))
     |> assign(:playlists, playlists)
     |> assign(:videos, videos)}
  end

  @impl true
  def handle_event("toggle-monitor", %{"id" => id, "type" => type}, socket) do
    case type do
      "channel" ->
        case Content.toggle_channel_monitor_status(id) do
          {:ok, channel} ->
            {:noreply,
             socket
             |> assign(:channel, channel)
             |> put_flash(:info, "Channel status updated.")}

          _ ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to update channel status.")}
        end

      "playlist" ->
        case Content.toggle_playlist_monitor_status(id) do
          {:ok, playlist} ->
            {
              :noreply,
              socket
              |> assign(:playlist, playlist)
              |> put_flash(:info, "Playlist status updated.")
            }

          _ ->
            {
              :noreply,
              socket
              |> put_flash(:error, "Failed to update playlist status.")
            }
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("queue-download", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete-video", _params, socket) do
    {:noreply, socket}
  end
end
