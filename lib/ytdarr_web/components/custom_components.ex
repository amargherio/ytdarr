defmodule YtdarrWeb.CustomComponents do
  use Phoenix.Component
  use Gettext, backend: YtdarrWeb.Gettext

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
            "object-cover object-top select-none pointer-events-none"
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
  defp banner_box_class(%{mode: "ratio", ratio: ratio}), do: "relative aspect-[#{ratio}] max-h-[30rem] min-h-[16rem]"
end
