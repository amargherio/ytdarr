defmodule YtdarrWeb.CustomComponents do
  use Phoenix.Component
  use Gettext, backend: YtdarrWeb.Gettext

  attr :variant, :string,
    values: ~w(primary secondary info success warning error),
    default: "primary"

  attr :size, :string, values: ~w(sm md lg), default: "md"
  attr :rest, :global, include: ~w(href navigate patch disabled)
  slot :inner_block, required: true

  def data_pill(assigns) do
    variants = %{
      "primary" => [
        "btn-primary",
        "text-primary-content bg-primary border-primary",
        "hover:bg-primary/90 hover:border-primary/90",
        "dark:bg-primary dark:border-primary dark:text-primary-content",
        "dark:hover:bg-primary/90 dark:hover:border-primary/90"
      ],
      "secondary" => [
        "btn-secondary",
        "text-secondary-content bg-secondary border-secondary",
        "hover:bg-secondary/90 hover:border-secondary/90",
        "dark:bg-secondary dark:border-secondary dark:text-secondary-content",
        "dark:hover:bg-secondary/90 dark:hover:border-secondary/90"
      ],
      "info" => [
        "btn-info",
        "text-info-content bg-info border-info",
        "hover:bg-info/90 hover:border-info/90",
        "dark:bg-info dark:border-info dark:text-info-content",
        "dark:hover:bg-info/90 dark:hover:border-info/90"
      ],
      "success" => [
        "btn-success",
        "text-success-content bg-success border-success",
        "hover:bg-success/90 hover:border-success/90",
        "dark:bg-success dark:border-success dark:text-success-content",
        "dark:hover:bg-success/90 dark:hover:border-success/90"
      ],
      "warning" => [
        "btn-warning",
        "text-warning-content bg-warning border-warning",
        "hover:bg-warning/90 hover:border-warning/90",
        "dark:bg-warning dark:border-warning dark:text-warning-content",
        "dark:hover:bg-warning/90 dark:hover:border-warning/90"
      ],
      "error" => [
        "btn-error",
        "text-error-content bg-error border-error",
        "hover:bg-error/90 hover:border-error/90",
        "dark:bg-error dark:border-error dark:text-error-content",
        "dark:hover:bg-error/90 dark:hover:border-error/90"
      ],
      nil => [
        "btn-primary btn-soft",
        "text-base-content bg-base-200 border-base-300",
        "hover:bg-base-300 hover:border-base-300",
        "dark:text-base-content dark:bg-base-200 dark:border-base-300",
        "dark:hover:bg-base-300 dark:hover:border-base-300"
      ]
    }

    sizes = %{
      "sm" => "btn-sm px-2 py-1 text-xs",
      "md" => "btn-md px-3 py-2 text-sm",
      "lg" => "btn-lg px-4 py-3 text-base"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [
          "btn",
          "rounded-full",
          "border",
          "font-medium",
          "transition-all duration-200",
          "focus:outline-none focus:ring-2 focus:ring-offset-2",
          "dark:focus:ring-offset-base-100",
          Map.fetch!(variants, assigns[:variant]),
          Map.fetch!(sizes, assigns[:size])
        ]
      end)

    if assigns.rest[:href] || assigns.rest[:navigate] || assigns.rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a header with hero styling, containing an avatar image, channel name, and description.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions
  attr :banner_url, :string, required: true

  # Optional Tailwind height classes to control the banner height (defaults to ~256-320px responsive)
  attr :height_class, :string, default: "h-64 md:h-80"
  # Optional overlay opacity class override (e.g. "bg-black/30"). Provided for flexibility.
  attr :overlay_class, :string, default: "bg-black/40"

  # Banner sizing strategy: "static" (use height_class), "fluid" (viewport clamp), "ratio" (aspect box)
  attr :mode, :string, values: ~w(static fluid ratio), default: "static"
  # Aspect ratio (only used when mode=="ratio") expressed as width/height, e.g. "21/5"
  attr :ratio, :string, default: "21/5"

  def hero_header(assigns) do
    assigns = assign(assigns, :banner_box_class, banner_box_class(assigns))

    ~H"""
    <header class={[@actions != [] && "flex flex-row items-center justify-between gap-6", "pb-4"]}>
      <div class={["w-full relative overflow-hidden rounded-lg", @banner_box_class]}>
        <img
          src={@banner_url}
          alt="Channel banner"
          class={[
            @mode == "ratio" && "absolute inset-0 w-full h-full",
            @mode != "ratio" && "w-full h-full",
            "object-cover object-center select-none pointer-events-none"
          ]}
          draggable="false"
        />
        <div class={["absolute inset-0", @overlay_class]}></div>
        <div class="absolute inset-0 flex items-center px-4">
          <div class="w-full max-w-6xl mx-auto flex flex-col md:flex-row md:items-center md:justify-between gap-6 text-white">
            <div class="flex-1 space-y-4 text-center md:text-left">
              {render_slot(@inner_block)}
            </div>
            <div class="flex flex-wrap justify-center md:justify-end gap-2 md:min-w-[12rem]">
              {render_slot(@actions)}
            </div>
          </div>
        </div>
      </div>
    </header>
    """
  end

  # -- Private helpers -------------------------------------------------------
  defp banner_box_class(%{mode: "static", height_class: hc}), do: hc
  defp banner_box_class(%{mode: "fluid"}), do: "h-[clamp(16rem,40vh,30rem)]"

  defp banner_box_class(%{mode: "ratio", ratio: ratio}),
    do: "relative aspect-[#{ratio}] max-h-[30rem] min-h-[16rem]"
end
