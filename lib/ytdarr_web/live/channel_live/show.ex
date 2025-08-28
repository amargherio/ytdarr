defmodule YtdarrWeb.ChannelLive.Show do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Channel {@channel.id}
        <:subtitle>This is a channel record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/channels"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/channels/#{@channel}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit channel
          </.button>
        </:actions>
      </.header>

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
    {:ok,
     socket
     |> assign(:page_title, "Show Channel")
     |> assign(:channel, Content.get_channel!(id))}
  end
end
