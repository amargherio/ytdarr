defmodule YtdarrWeb.ChannelLive.Add do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Add Channel")
     |> assign(:search, "")
     |> assign(:results, [])
     |> assign(:loading?, false)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    # TODO: Replace with real YouTube API lookup.
    results = mock_youtube_search(q)
  {:noreply,
   socket
   |> assign(:search, q)
   |> assign(:results, results)
   |> assign(:loading?, false)}
  end

  def handle_event("queue-search", %{"q" => q}, socket) do
    # For future async handling (Task + handle_info) if needed
    {:noreply, assign(socket, search: q, loading?: true)}
  end

  def handle_event("add", %{"external_id" => external_id, "name" => name, "url" => url}, socket) do
    attrs = %{
      name: name,
      external_id: external_id,
      url: url,
      platform: "YouTube"
    }

    case Content.create_channel(attrs) do
      {:ok, channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel added")
         |> push_navigate(to: ~p"/channels/#{channel}")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, Enum.map_join(changeset.errors, ", ", fn {f, {m, _}} -> "#{f} #{m}" end))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channels}>
      <.header>
        Add Channel
        <:subtitle>Search YouTube and add a channel to monitor.</:subtitle>
        <:actions>
          <.button navigate={~p"/channels"}>Back</.button>
        </:actions>
      </.header>

      <div class="space-y-6">
        <form phx-change="search" phx-submit="noop" class="flex flex-col gap-2">
          <input
            type="text"
            name="q"
            value={@search}
            placeholder="Search YouTube channels..."
            class="input input-bordered"
            phx-debounce="400"
          />
          <p class="text-xs opacity-60">Type to search. (Mocked data for now.)</p>
        </form>

        <div :if={@loading?} class="flex items-center gap-2 text-sm">
          <span class="loading loading-spinner loading-sm" /> Searching...
        </div>

        <div :if={@results == [] and @search != "" and !@loading?} class="text-sm opacity-70">
          No results.
        </div>

        <div :if={@results != []} class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Avatar</th>
                <th>Name</th>
                <th>External ID</th>
                <th>Subscribers</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @results}>
                <td>
                  <img :if={r.avatar_url} src={r.avatar_url} class="w-10 h-10 rounded-full" />
                </td>
                <td>{r.name}</td>
                <td><code>{r.external_id}</code></td>
                <td>{r.subscriber_count}</td>
                <td>
                  <.button phx-click="add" phx-value-external_id={r.external_id} phx-value-name={r.name} phx-value-url={r.url} variant="primary" class="btn-xs">
                    Add
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp mock_youtube_search(""), do: []
  defp mock_youtube_search(nil), do: []
  defp mock_youtube_search(query) do
    base = String.replace(query, ~r/\s+/, "-") |> String.downcase()

    for i <- 1..min(5, String.length(query)) do
      %{
        name: "#{String.capitalize(query)} Channel #{i}",
        external_id: "mock-#{base}-#{i}",
        url: "https://www.youtube.com/@#{base}#{i}",
        avatar_url: "https://via.placeholder.com/64?text=#{URI.encode(query)}",
        subscriber_count: Enum.random(1_000..100_000) |> :erlang.integer_to_binary()
      }
    end
  end
end
