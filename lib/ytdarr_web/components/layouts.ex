defmodule YtdarrWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use YtdarrWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :nav, :atom,
    default: nil,
    doc: "current nav section for highlighting (e.g. :dashboard, :channels)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden">
      <aside class="hidden md:flex md:flex-col w-56 bg-base-200 border-r border-base-300">
        <div class="flex items-center gap-2 p-4 h-16 border-b border-base-300">
          <a href={~p"/dashboard"} class="inline-flex items-center gap-2 font-semibold">
            <img src={~p"/images/logo.svg"} width="32" />
            <span>Ytdarr</span>
          </a>
        </div>
        <nav class="flex-1 overflow-y-auto py-4">
          <ul class="menu px-2 text-sm">
            <li>
              <a href={~p"/dashboard"} class={[@nav == :dashboard && "active font-semibold"]}>
                <span class="hero-chart-bar" /> Dashboard
              </a>
            </li>
            <li>
              <a href={~p"/content/add"} class={[@nav == :content_add && "active font-semibold"]}>Add Content</a>
            </li>
            <li>
              <details open={@nav in [:channels, :channel_add]}>
                <summary class={[@nav == :channels && "active font-semibold", @nav == :channel_add && "font-semibold"]}>Channels</summary>
                <ul>
                  <li>
                    <a href={~p"/channels"} class={[@nav == :channels && "active font-semibold"]}>All Channels</a>
                  </li>
                  <li>
                    <a href={~p"/channels/add"} class={[@nav == :channel_add && "active font-semibold"]}>Add Channel</a>
                  </li>
                </ul>
              </details>
            </li>
            <li>
              <a href={~p"/queue"} class={[@nav == :queue_view && "active font-semibold"]}>Download Queue</a>
            </li>
            <li>
              <a href={~p"/oban"} target="_blank">Oban Jobs</a>
            </li>
          </ul>
        </nav>
        <div class="p-4 border-t border-base-300 flex items-center justify-between text-xs">
          <span>Phoenix v{Application.spec(:phoenix, :vsn)}</span>
          <.theme_toggle />
        </div>
      </aside>
      <div class="flex flex-col flex-1 min-w-0">
        <header class="flex md:hidden items-center justify-between gap-2 p-3 border-b border-base-300 bg-base-200">
          <a href={~p"/dashboard"} class="inline-flex items-center gap-2 font-semibold">
            <img src={~p"/images/logo.svg"} width="28" />
            <span>Ytdarr</span>
          </a>
          <div class="flex items-center gap-2">
            <.theme_toggle />
          </div>
        </header>
        <main class="flex-1 overflow-y-auto p-6 space-y-4">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
