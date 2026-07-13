defmodule YtdarrWeb.SettingsLive.Components do
  use YtdarrWeb, :html

  attr :active, :atom, required: true
  attr :items, :list, required: true

  def category_navigation(assigns) do
    ~H"""
    <nav id="settings-category-navigation" aria-label="Settings categories">
      <label class="fieldset mb-5 lg:hidden">
        <span class="label mb-1">Settings category</span>
        <select
          id="settings-category-select"
          name="category"
          class="select w-full"
          phx-change="navigate-category"
        >
          <option
            :for={item <- @items}
            value={item.id}
            selected={item.id == @active}
          >
            {item.label}
          </option>
        </select>
      </label>

      <div class="hidden lg:block">
        <p class="px-3 pb-2 text-xs font-semibold uppercase tracking-wider text-base-content/45">
          Configuration
        </p>
        <ul class="space-y-1">
          <li :for={item <- @items}>
            <.link
              id={"settings-category-#{item.id}"}
              patch={~p"/settings?category=#{item.id}"}
              aria-current={item.id == @active && "page"}
              class={[
                "group flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors duration-150",
                "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                if(item.id == @active,
                  do: "bg-primary/10 font-semibold text-primary",
                  else: "text-base-content/75 hover:bg-base-300/60 hover:text-base-content"
                )
              ]}
            >
              <.icon name={item.icon} class="size-4 shrink-0" />
              <span>{item.label}</span>
            </.link>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  slot :actions

  def section_header(assigns) do
    ~H"""
    <header class="flex flex-col gap-4 border-b border-base-300 pb-5 sm:flex-row sm:items-start sm:justify-between">
      <div class="flex min-w-0 items-start gap-3">
        <div class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg bg-base-200 text-base-content/70">
          <.icon name={@icon} class="size-5" />
        </div>
        <div class="min-w-0">
          <h2 class="text-xl font-semibold tracking-tight text-base-content">{@title}</h2>
          <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/65">{@description}</p>
        </div>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :status, :atom, required: true

  def effect_badge(assigns) do
    {label, icon, classes} =
      case assigns.status do
        :immediate ->
          {"Applies immediately", "hero-bolt", "bg-success/15 text-success"}

        :new_items ->
          {"Applies to new items", "hero-forward", "bg-info/15 text-info"}

        :next_schedule ->
          {"Applies on next schedule", "hero-clock", "bg-info/15 text-info"}

        :environment ->
          {"Environment managed", "hero-command-line", "bg-warning/15 text-warning"}

        :restart_required ->
          {"Restart required", "hero-arrow-path", "bg-warning/15 text-warning"}

        :stored_only ->
          {"Stored only", "hero-circle-stack", "bg-base-300 text-base-content/65"}

        _ ->
          {"Status unavailable", "hero-question-mark-circle", "bg-base-300 text-base-content/65"}
      end

    assigns = assign(assigns, label: label, icon: icon, classes: classes)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-xs font-medium",
      @classes
    ]}>
      <.icon name={@icon} class="size-3.5" />
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :effect, :atom, required: true
  attr :id, :string, required: true
  slot :control, required: true

  def setting_row(assigns) do
    ~H"""
    <div
      id={@id}
      class="grid gap-4 border-b border-base-300 py-5 last:border-b-0 md:grid-cols-[minmax(0,1fr)_minmax(15rem,24rem)] md:items-start"
    >
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <h2 class="text-sm font-semibold text-base-content">{@label}</h2>
          <.effect_badge status={@effect} />
        </div>
        <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/60">{@description}</p>
      </div>
      <div class="min-w-0">{render_slot(@control)}</div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :close, Phoenix.LiveView.JS, required: true
  attr :return_focus, :string, required: true
  slot :inner_block, required: true

  def editor_panel(assigns) do
    ~H"""
    <aside
      id={@id}
      aria-label={@title}
      class="min-w-0 border-t border-base-300 bg-base-200/65 p-4 lg:sticky lg:top-4 lg:max-h-[calc(100vh-7rem)] lg:overflow-y-auto lg:rounded-xl lg:border"
      phx-mounted={Phoenix.LiveView.JS.focus_first(to: "##{@id}")}
      phx-remove={Phoenix.LiveView.JS.focus(to: @return_focus)}
    >
      <div class="mb-5 flex items-start justify-between gap-4">
        <div>
          <h2 class="text-base font-semibold text-base-content">{@title}</h2>
          <p :if={@description} class="mt-1 text-sm leading-5 text-base-content/60">
            {@description}
          </p>
        </div>
        <button
          id="settings-editor-close"
          type="button"
          class="btn btn-ghost btn-sm btn-square shrink-0"
          phx-click={@close}
          aria-label="Close editor"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
      {render_slot(@inner_block)}
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, default: "hero-plus-circle"
  slot :action, required: true

  def empty_state(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex flex-col items-start gap-3 rounded-xl border border-dashed border-base-300 bg-base-200/35 p-6"
    >
      <div class="flex size-10 items-center justify-center rounded-lg bg-base-300 text-base-content/55">
        <.icon name={@icon} class="size-5" />
      </div>
      <div>
        <h3 class="font-semibold text-base-content">{@title}</h3>
        <p class="mt-1 max-w-xl text-sm leading-6 text-base-content/60">{@description}</p>
      </div>
      <div>{render_slot(@action)}</div>
    </div>
    """
  end

  attr :section, :string, required: true
  attr :form_id, :string, required: true

  def save_bar(assigns) do
    ~H"""
    <div
      id="settings-save-bar"
      class="sticky bottom-3 z-20 mt-6 flex flex-col gap-3 rounded-xl border border-base-300 bg-base-100/95 p-3 shadow-lg shadow-base-300/20 backdrop-blur-sm sm:flex-row sm:items-center sm:justify-between"
      role="status"
    >
      <div class="flex items-center gap-2 text-sm">
        <span class="flex size-7 items-center justify-center rounded-full bg-warning/15 text-warning">
          <.icon name="hero-pencil-square" class="size-4" />
        </span>
        <span><strong>{@section}</strong> has unsaved changes.</span>
      </div>
      <div class="flex items-center gap-2">
        <button
          id="settings-discard-changes"
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="discard-section-changes"
        >
          Discard
        </button>
        <button
          id="settings-save-changes"
          type="submit"
          form={@form_id}
          class="btn btn-primary btn-sm"
          phx-disable-with="Saving..."
        >
          Save changes
        </button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :description, :string, default: nil
  attr :sensitive, :boolean, default: false
  attr :status, :atom, default: nil

  def system_row(assigns) do
    ~H"""
    <div
      id={@id}
      class="grid gap-2 border-b border-base-300 py-4 last:border-b-0 sm:grid-cols-[12rem_minmax(0,1fr)] sm:gap-5"
    >
      <div>
        <p class="text-sm font-medium text-base-content">{@label}</p>
        <p :if={@description} class="mt-1 text-xs leading-5 text-base-content/50">{@description}</p>
      </div>
      <div class="flex min-w-0 flex-wrap items-center gap-2 sm:justify-end">
        <code class="min-w-0 break-all rounded-md bg-base-300 px-2 py-1 text-xs text-base-content/75">
          {if(@sensitive, do: "Configured", else: @value)}
        </code>
        <.effect_badge :if={@status} status={@status} />
      </div>
    </div>
    """
  end
end
