defmodule YtdarrWeb.DashboardLive.Index do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  require Ash.Query

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :ok

    full_list = list_monitored_channels_with_videos()
    first_slice = Enum.take(full_list, @page_size)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:search, "")
     # 1-based
     |> assign(:page, 1)
     |> assign(:channels_cache, full_list)
     |> assign(:end_of_list?, length(full_list) <= @page_size)
     |> stream(:channels, first_slice)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    full_list = search_monitored_channels_with_videos(q)
    first_slice = Enum.take(full_list, @page_size)

    {:noreply,
     socket
     |> assign(:search, q)
     |> assign(:page, 1)
     |> assign(:channels_cache, full_list)
     |> assign(:end_of_list?, length(full_list) <= @page_size)
     |> stream(:channels, [], reset: true)
     |> stream(:channels, first_slice)}
  end

  def handle_event("load-more", _params, %{assigns: %{end_of_list?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load-more", _params, socket) do
    next_page = socket.assigns.page + 1
    already_loaded = socket.assigns.page * @page_size
    next_slice = socket.assigns.channels_cache |> Enum.slice(already_loaded, @page_size)

    {:noreply,
     socket
     |> assign(:page, next_page)
     |> assign(
       :end_of_list?,
       already_loaded + length(next_slice) >= length(socket.assigns.channels_cache)
     )
     |> stream(:channels, next_slice)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:dashboard}>
      <.header>
        Dashboard
        <:subtitle>Overview of monitored channels</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/channels/new"}>
            <.icon name="hero-plus" /> Add Channel
          </.button>
        </:actions>
      </.header>
      <div class="flex flex-col gap-4" id="infinite-scroll-container" phx-hook="InfiniteScroll">
        <div class="form-control">
          <label class="label"><span class="label-text">Search Channels</span></label>
          <input
            name="q"
            type="text"
            value={@search}
            phx-change="search"
            phx-debounce="300"
            class="input input-bordered w-full"
            placeholder="Search by name or external id"
          />
        </div>

        <.table
          id="dashboard-channels"
          rows={@streams.channels}
          row_click={fn {_id, channel} -> JS.navigate(~p"/channels/#{channel}") end}
        >
          <:col :let={{_id, channel}} label="Avatar">
            <img :if={channel.avatar_url} src={channel.avatar_url} class="w-10 h-10 rounded-full" />
            <div :if={!channel.avatar_url} class="avatar placeholder">
              <div class="bg-neutral text-neutral-content rounded-full w-10">
                <span>{String.first(channel.name || "?")}</span>
              </div>
            </div>
          </:col>
          <:col :let={{_id, channel}} label="Name">{channel.name}</:col>
          <:col :let={{_id, channel}} label="Platform">{channel.platform}</:col>
          <:col :let={{_id, channel}} label="Videos">{length(channel.videos || [])}</:col>
          <:col :let={{_id, channel}} label="Monitored Since">
            {format_datetime(channel.is_monitored_since)}
          </:col>
          <:action :let={{_id, channel}}>
            <.link navigate={~p"/channels/#{channel}"} class="link link-primary">View</.link>
          </:action>
        </.table>

        <div
          id="infinite-scroll-marker"
          data-end={@end_of_list?}
          class="flex items-center justify-center h-12 text-sm text-base-content/60"
        >
          <span :if={@end_of_list?}>No more channels</span>
          <span :if={!@end_of_list?} class="loading loading-spinner loading-sm" />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_datetime(_), do: "—"

  defp list_monitored_channels_with_videos do
    Content.list_channels!(
      query: [filter: [is_monitored: true], sort: [name: :asc]],
      load: [:videos]
    )
  end

  defp search_monitored_channels_with_videos(query) when query in [nil, ""] do
    list_monitored_channels_with_videos()
  end

  defp search_monitored_channels_with_videos(query) do
    like = "%#{query}%"

    Content.Channel
    |> Ash.Query.filter(is_monitored == true)
    |> Ash.Query.filter(contains(name, ^like) or contains(external_id, ^like))
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.load([:videos])
    |> Ash.read!()
  end
end
