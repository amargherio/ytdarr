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
      <%!-- Desktop sidebar --%>
      <aside class="hidden md:flex md:flex-col w-56 bg-base-200 border-r border-base-300 flex-shrink-0">
        <div class="flex items-center gap-2 p-4 h-14 border-b border-base-300">
          <a
            href={~p"/dashboard"}
            class="inline-flex items-center gap-2 font-semibold text-base-content hover:text-primary transition-colors"
          >
            <img src={~p"/images/logo.svg"} width="28" />
            <span>Ytdarr</span>
          </a>
        </div>
        <nav class="flex-1 overflow-y-auto py-3">
          <ul class="menu px-2 text-sm gap-0.5">
            <li>
              <a
                href={~p"/dashboard"}
                class={[
                  "flex items-center gap-2 rounded-lg px-3 py-2 transition-colors duration-150",
                  "hover:bg-base-300/60",
                  @nav == :dashboard && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-chart-bar" class="size-4" /> Dashboard
              </a>
            </li>
            <li>
              <details open={@nav in [:channels, :channel_add]}>
                <summary class={[
                  "flex items-center gap-2 rounded-lg px-3 py-2 transition-colors duration-150 cursor-pointer",
                  "hover:bg-base-300/60",
                  @nav in [:channels, :channel_add] && "font-semibold"
                ]}>
                  <.icon name="hero-tv" class="size-4" /> Channels
                </summary>
                <ul class="ml-4 mt-1 space-y-0.5">
                  <li>
                    <a
                      href={~p"/channels"}
                      class={[
                        "flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm transition-colors duration-150",
                        "hover:bg-base-300/60",
                        @nav == :channels && "bg-primary/10 text-primary font-semibold"
                      ]}
                    >
                      All Channels
                    </a>
                  </li>
                  <li>
                    <a
                      href={~p"/channels/add"}
                      class={[
                        "flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm transition-colors duration-150",
                        "hover:bg-base-300/60",
                        @nav == :channel_add && "bg-primary/10 text-primary font-semibold"
                      ]}
                    >
                      Add Channel
                    </a>
                  </li>
                </ul>
              </details>
            </li>
            <li>
              <a
                href={~p"/queue"}
                class={[
                  "flex items-center gap-2 rounded-lg px-3 py-2 transition-colors duration-150",
                  "hover:bg-base-300/60",
                  @nav == :queue && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Queue
              </a>
            </li>
            <li>
              <a
                href={~p"/settings"}
                class={[
                  "flex items-center gap-2 rounded-lg px-3 py-2 transition-colors duration-150",
                  "hover:bg-base-300/60",
                  @nav == :settings && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
              </a>
            </li>
            <li>
              <a
                href={~p"/oban"}
                target="_blank"
                class="flex items-center gap-2 rounded-lg px-3 py-2 transition-colors duration-150 hover:bg-base-300/60"
              >
                <.icon name="hero-queue-list" class="size-4" /> Oban Jobs
                <.icon name="hero-arrow-top-right-on-square" class="size-3 ml-auto opacity-50" />
              </a>
            </li>
          </ul>
        </nav>
        <div class="p-3 border-t border-base-300 flex items-center justify-between text-xs text-base-content/50">
          <span>Phoenix v{Application.spec(:phoenix, :vsn)}</span>
        </div>
      </aside>

      <%!-- Mobile sidebar drawer (hidden by default) --%>
      <div
        id="mobile-sidebar-backdrop"
        class="fixed inset-0 z-40 bg-black/50 hidden md:hidden"
        phx-click={
          JS.add_class("hidden", to: "#mobile-sidebar-backdrop")
          |> JS.add_class("hidden", to: "#mobile-sidebar")
        }
      >
      </div>
      <aside
        id="mobile-sidebar"
        class="fixed inset-y-0 left-0 z-50 w-64 bg-base-200 border-r border-base-300 hidden md:hidden transform transition-transform duration-200 overflow-y-auto"
      >
        <div class="flex items-center justify-between p-4 h-14 border-b border-base-300">
          <a
            href={~p"/dashboard"}
            class="inline-flex items-center gap-2 font-semibold text-base-content"
          >
            <img src={~p"/images/logo.svg"} width="28" />
            <span>Ytdarr</span>
          </a>
          <button
            class="btn btn-ghost btn-sm btn-square"
            phx-click={
              JS.add_class("hidden", to: "#mobile-sidebar-backdrop")
              |> JS.add_class("hidden", to: "#mobile-sidebar")
            }
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <nav class="py-3">
          <ul class="menu px-2 text-sm gap-0.5">
            <li>
              <a
                href={~p"/dashboard"}
                class={[
                  "rounded-lg px-3 py-2",
                  @nav == :dashboard && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-chart-bar" class="size-4" /> Dashboard
              </a>
            </li>
            <li>
              <a
                href={~p"/channels"}
                class={[
                  "rounded-lg px-3 py-2",
                  @nav == :channels && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-tv" class="size-4" /> All Channels
              </a>
            </li>
            <li>
              <a
                href={~p"/channels/add"}
                class={[
                  "rounded-lg px-3 py-2",
                  @nav == :channel_add && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-plus-circle" class="size-4" /> Add Channel
              </a>
            </li>
            <li>
              <a
                href={~p"/queue"}
                class={[
                  "rounded-lg px-3 py-2",
                  @nav == :queue && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Queue
              </a>
            </li>
            <li>
              <a
                href={~p"/settings"}
                class={[
                  "rounded-lg px-3 py-2",
                  @nav == :settings && "bg-primary/10 text-primary font-semibold"
                ]}
              >
                <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
              </a>
            </li>
            <li>
              <a href={~p"/oban"} target="_blank" class="rounded-lg px-3 py-2">
                <.icon name="hero-queue-list" class="size-4" /> Oban Jobs
              </a>
            </li>
          </ul>
        </nav>
      </aside>

      <%!-- Main content area --%>
      <div class="flex flex-col flex-1 min-w-0">
        <%!-- Sticky header with search + actions --%>
        <header class="sticky top-0 z-30 flex items-center gap-3 px-4 py-2.5 bg-base-100 border-b border-base-300">
          <%!-- Hamburger (mobile only) --%>
          <button
            class="btn btn-ghost btn-sm btn-square md:hidden flex-shrink-0"
            phx-click={
              JS.remove_class("hidden", to: "#mobile-sidebar-backdrop")
              |> JS.remove_class("hidden", to: "#mobile-sidebar")
            }
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>

          <%!-- Omnisearch bar --%>
          <.live_component module={YtdarrWeb.OmnisearchComponent} id="omnisearch" />

          <%!-- Header actions --%>
          <div class="flex items-center gap-2 flex-shrink-0">
            <.theme_toggle />
          </div>
        </header>

        <%!-- Page content --%>
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
