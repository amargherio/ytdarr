defmodule YtdarrWeb.OmnisearchComponent do
  @moduledoc """
  Omnisearch LiveComponent that searches channels, playlists, and videos
  in the local database. Rendered inside the app layout header.

  Features:
  - Debounced search (200ms) with grouped results by type
  - Keyboard navigation (Arrow Up/Down, Enter, Escape)
  - "Add Channel" fallback link when no results match
  - "/" keyboard shortcut via OmniSearch JS hook
  """
  use YtdarrWeb, :live_component

  alias Ytdarr.Content

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:results, %{channels: [], playlists: [], videos: []})
     |> assign(:open?, false)
     |> assign(:selected_index, -1)
     |> assign(:result_count, 0)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="OmniSearch" class="relative flex-1 max-w-xl">
      <form
        id={"#{@id}-form"}
        phx-change="search"
        phx-submit="go"
        phx-target={@myself}
        class="relative"
      >
        <.icon
          name="hero-magnifying-glass"
          class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-base-content/50"
        />
        <input
          id={"#{@id}-input"}
          type="text"
          name="q"
          value={@query}
          data-omnisearch-input
          placeholder="Search channels, playlists, videos… (press /)"
          autocomplete="off"
          phx-debounce="200"
          phx-keydown="keydown"
          phx-target={@myself}
          phx-click-away="close"
          role="combobox"
          aria-label="Search channels, playlists, and videos"
          aria-expanded={to_string(@open?)}
          aria-controls="omnisearch-results"
          aria-activedescendant={
            if(@selected_index >= 0, do: "omnisearch-item-#{@selected_index}", else: nil)
          }
          class={[
            "w-full pl-10 pr-4 py-2 rounded-full text-sm",
            "bg-base-200 border border-base-300",
            "placeholder:text-base-content/40",
            "focus:outline-none focus:ring-2 focus:ring-primary/50 focus:border-primary/50",
            "transition-all duration-200"
          ]}
        />
      </form>

      <%= if @open? do %>
        <div
          id="omnisearch-results"
          role="listbox"
          class={[
            "absolute top-full left-0 right-0 mt-2 z-50",
            "bg-base-100 border border-base-300 rounded-xl shadow-xl",
            "max-h-96 overflow-y-auto",
            "animate-in fade-in slide-in-from-top-1 duration-150"
          ]}
        >
          <%= if @result_count == 0 do %>
            <div class="p-4 text-center">
              <p class="text-sm text-base-content/60 mb-2">No results found</p>
              <.link
                navigate="/channels/add"
                class="inline-flex items-center gap-1 text-sm font-medium text-primary hover:text-primary/80 transition-colors"
              >
                <.icon name="hero-plus-circle" class="size-4" /> Add a new channel
              </.link>
            </div>
          <% else %>
            <%!-- Channels section --%>
            <%= if @results.channels != [] do %>
              <div class="px-3 pt-3 pb-1">
                <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                  Channels
                </span>
              </div>
              <%= for {channel, idx} <- Enum.with_index(@results.channels) do %>
                <.link
                  navigate={"/channels/#{channel.id}"}
                  id={"omnisearch-item-#{idx}"}
                  role="option"
                  aria-selected={to_string(@selected_index == idx)}
                  class={[
                    "flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors",
                    if(@selected_index == idx, do: "bg-primary/10", else: "hover:bg-base-200")
                  ]}
                >
                  <div class="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                    <.icon name="hero-tv" class="size-4 text-primary" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate">{channel.name}</div>
                    <div class="text-xs text-base-content/50 truncate">
                      {channel.platform_username || channel.external_id}
                    </div>
                  </div>
                  <%= if channel.is_monitored do %>
                    <.icon name="hero-bookmark-solid" class="size-4 text-success flex-shrink-0" />
                  <% end %>
                </.link>
              <% end %>
            <% end %>

            <%!-- Playlists section --%>
            <%= if @results.playlists != [] do %>
              <% channel_offset = length(@results.channels) %>
              <div class="px-3 pt-3 pb-1 border-t border-base-200">
                <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                  Playlists
                </span>
              </div>
              <%= for {playlist, raw_idx} <- Enum.with_index(@results.playlists) do %>
                <% idx = channel_offset + raw_idx %>
                <.link
                  navigate={"/channels/#{playlist.channel_id}"}
                  id={"omnisearch-item-#{idx}"}
                  role="option"
                  aria-selected={to_string(@selected_index == idx)}
                  class={[
                    "flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors",
                    if(@selected_index == idx, do: "bg-primary/10", else: "hover:bg-base-200")
                  ]}
                >
                  <div class="flex-shrink-0 w-8 h-8 rounded-lg bg-info/10 flex items-center justify-center">
                    <.icon name="hero-queue-list" class="size-4 text-info" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate">{playlist.name}</div>
                    <div class="text-xs text-base-content/50 truncate">
                      {if(Ash.Resource.loaded?(playlist, :channel),
                        do: playlist.channel.name,
                        else: ""
                      )}
                    </div>
                  </div>
                </.link>
              <% end %>
            <% end %>

            <%!-- Videos section --%>
            <%= if @results.videos != [] do %>
              <% video_offset = length(@results.channels) + length(@results.playlists) %>
              <div class="px-3 pt-3 pb-1 border-t border-base-200">
                <span class="text-xs font-semibold uppercase tracking-wider text-base-content/50">
                  Videos
                </span>
              </div>
              <%= for {video, raw_idx} <- Enum.with_index(@results.videos) do %>
                <% idx = video_offset + raw_idx %>
                <.link
                  navigate={"/channels/#{video.channel_id}"}
                  id={"omnisearch-item-#{idx}"}
                  role="option"
                  aria-selected={to_string(@selected_index == idx)}
                  class={[
                    "flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors",
                    if(@selected_index == idx, do: "bg-primary/10", else: "hover:bg-base-200")
                  ]}
                >
                  <div class="flex-shrink-0 w-8 h-8 rounded-lg bg-warning/10 flex items-center justify-center">
                    <.icon name="hero-play" class="size-4 text-warning" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate">{video.title}</div>
                    <div class="text-xs text-base-content/50 truncate">
                      {if(Ash.Resource.loaded?(video, :channel), do: video.channel.name, else: "")}
                    </div>
                  </div>
                </.link>
              <% end %>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      results = Content.omnisearch(query)
      count = length(results.channels) + length(results.playlists) + length(results.videos)

      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:results, results)
       |> assign(:result_count, count)
       |> assign(:open?, true)
       |> assign(:selected_index, -1)}
    else
      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:results, %{channels: [], playlists: [], videos: []})
       |> assign(:result_count, 0)
       |> assign(:open?, false)
       |> assign(:selected_index, -1)}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, open?: false, selected_index: -1)}
  end

  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    max = socket.assigns.result_count - 1
    new_idx = min(socket.assigns.selected_index + 1, max)
    {:noreply, assign(socket, :selected_index, new_idx)}
  end

  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    new_idx = max(socket.assigns.selected_index - 1, -1)
    {:noreply, assign(socket, :selected_index, new_idx)}
  end

  def handle_event("keydown", %{"key" => "Enter"}, socket) do
    idx = socket.assigns.selected_index

    if idx >= 0 do
      url = result_url_at(socket.assigns.results, idx)

      if url do
        {:noreply,
         socket
         |> assign(:open?, false)
         |> push_navigate(to: url)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("go", _params, socket) do
    # Form submit — navigate to first result if one exists
    idx = max(socket.assigns.selected_index, 0)
    url = result_url_at(socket.assigns.results, idx)

    if url do
      {:noreply,
       socket
       |> assign(:open?, false)
       |> push_navigate(to: url)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open?: false, selected_index: -1)}
  end

  # Returns the navigation URL for the result at the given flat index
  defp result_url_at(results, idx) do
    all_items =
      Enum.map(results.channels, fn c -> "/channels/#{c.id}" end) ++
        Enum.map(results.playlists, fn p -> "/channels/#{p.channel_id}" end) ++
        Enum.map(results.videos, fn v -> "/channels/#{v.channel_id}" end)

    Enum.at(all_items, idx)
  end
end
