defmodule YtdarrWeb.ChannelLive.Index do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Channels
        <:actions>
          <.button variant="primary" navigate={~p"/channels/new"}>
            <.icon name="hero-plus" /> New Channel
          </.button>
        </:actions>
      </.header>

      <.table
        id="channels"
        rows={@streams.channels}
        row_click={fn {_id, channel} -> JS.navigate(~p"/channels/#{channel}") end}
      >
        <:col :let={{_id, channel}} label="Name">{channel.name}</:col>
        <:col :let={{_id, channel}} label="External">{channel.external_id}</:col>
        <:col :let={{_id, channel}} label="Url">{channel.url}</:col>
        <:col :let={{_id, channel}} label="Description">{channel.description}</:col>
        <:col :let={{_id, channel}} label="Platform">{channel.platform}</:col>
        <:col :let={{_id, channel}} label="Avatar url">{channel.avatar_url}</:col>
        <:col :let={{_id, channel}} label="Is monitored">{channel.is_monitored}</:col>
        <:col :let={{_id, channel}} label="Is monitored since">{channel.is_monitored_since}</:col>
        <:col :let={{_id, channel}} label="Last checked at">{channel.last_checked_at}</:col>
        <:col :let={{_id, channel}} label="Base path">{channel.base_path}</:col>
        <:col :let={{_id, channel}} label="Generic video path">{channel.generic_video_path}</:col>
        <:action :let={{_id, channel}}>
          <div class="sr-only">
            <.link navigate={~p"/channels/#{channel}"}>Show</.link>
          </div>
          <.link navigate={~p"/channels/#{channel}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, channel}}>
          <.link
            phx-click={JS.push("delete", value: %{id: channel.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Channels")
     |> stream(:channels, Content.list_channels())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    channel = Content.get_channel!(id)
    {:ok, _} = Content.delete_channel(channel)

    {:noreply, stream_delete(socket, :channels, channel)}
  end
end
