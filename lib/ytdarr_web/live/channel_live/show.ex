defmodule YtdarrWeb.ChannelLive.Show do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channels}>
      <.hero_header banner_url={@channel.banner_url}>
        <div class="left-06">
          <h1 class="mb-5 text-5xl font-bold">{@channel.name}</h1>
          <p class="mb-5">{@channel.description}</p>
        </div>
        <:actions>
          <div class="flex flex-col flex-wrap justify-center gap-2">
            <%!-- <.button navigate={~p"/channels"}>
              <.icon name="hero-arrow-left" />
            </.button> --%>
            <.button variant="primary" navigate={~p"/channels/#{@channel}/edit?return_to=show"}>
              <.icon name="hero-pencil-square" /> Edit channel
            </.button>
          </div>
        </:actions>
      </.hero_header>

      <!-- channel metadata -->
      <div class="flex flex-wrap justify-start gap-4">
        <div class="bg-slate-200 p-2 rounded">
          <.icon name="hero-folder-arrow-down" /> {@channel.base_path}
        </div>
        <div class="bg-slate-200 p-2 rounded">
          <%= if @channel.is_monitored do %>
            <.icon name="hero-bookmark-solid" /> Monitored
          <% else %>
            <.icon name="hero-bookmark" /> Not Monitored
          <% end %>
        </div>
        <div class="bg-slate-200 p-2 rounded">
          <.icon name="hero-clock" /> Last checked at: {@channel.last_checked_at}
        </div>
        <div class="bg-slate-200 p-2 rounded">
          <.icon name="hero-link" /> <a href={@channel.url}>{@channel.platform_username}</a>
        </div>
      </div>


      <%= for playlist <- @playlists do %>
      <div tabindex="0" class="collapse collapse-arrow bg-base-100 border-base-300 border">
        <div class="collapse-title text-xl font-medium after:start-5 after:end-auto pe-4 ps-12">{playlist.name}</div>
        <div class="collapse-content">
          <.table id={"videos-#{playlist.id}"} rows={playlist.videos}>
            <:col :let={video} label="Title"><%= video.title %></:col>
            <:col :let={video} label="Upload Date"><%= video.upload_date %></:col>
            <:col :let={video} label="Status"><%= video.is_downloaded %></:col>
          </.table>
        </div>
      </div>
      <% end %>

      <div tabindex="0" class="collapse collapse-arrow bg-base-100 border-base-300 border">
        <div class="collapse-title text-xl font-medium after:start-5 after:end-auto pe-4 ps-12">Videos</div>
        <div class="collapse-content">
          <.table id="videos" rows={@videos}>
            <:col :let={video} label="Title"><%= video.title %></:col>
            <:col :let={video} label="Upload Date"><%= video.upload_date %></:col>
            <:col :let={video} label="Status"><%= video.is_downloaded %></:col>
          </.table>
        </div>
      </div>


      <.list>
        <:item title="Name">{@channel.name}</:item>
        <:item title="External">{@channel.external_id}</:item>
        <:item title="Url">{@channel.url}</:item>
        <:item title="Description">{@channel.description}</:item>
        <:item title="Platform">{@channel.platform}</:item>
        <:item title="Avatar url">{@channel.avatar_url}</:item>
        <:item title="Is monitored">{@channel.is_monitored}</:item>
        <:item title="Is monitored since">{@channel.is_monitored_since}</:item>
        <:item title="Last checked at">{@channel.last_checked_at}</:item>
        <:item title="Base path">{@channel.base_path}</:item>
        <:item title="Generic video path">{@channel.generic_video_path}</:item>
      </.list>
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
end
