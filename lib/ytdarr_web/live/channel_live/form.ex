defmodule YtdarrWeb.ChannelLive.Form do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content
  alias Ytdarr.Content.Channel

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channels}>
      <.header>
        Editing Channel: {@channel.name}
      </.header>

      <.form for={@form} id="channel-form" phx-change="validate" phx-submit="save">
        <div class="bg-slate-200 p-4 rounded-md">
          <h2>Metadata</h2>

          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:url]} type="text" label="Url" />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input field={@form[:platform]} type="text" label="Platform" />
          <.input field={@form[:avatar_url]} type="text" label="Avatar url" />
          <.input field={@form[:platform_username]} type="text" label="Platform Username" />
        </div>

        <div class="p-4 rounded-md">
          <h2>File Information</h2>

          <.input field={@form[:base_path]} type="text" label="Base path" />
          <.input field={@form[:generic_video_path]} type="text" label="Generic video path" />
        </div>

        <.input field={@form[:is_monitored]} type="checkbox" label="Is monitored" />

        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Channel</.button>
          <.button navigate={return_path(@return_to, @channel)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    channel = Content.get_channel!(id)

    socket
    |> assign(:page_title, "Edit Channel")
    |> assign(:channel, channel)
    |> assign(:form, Content.form_to_update_channel(channel) |> to_form())
  end

  defp apply_action(socket, :new, _params) do
    channel = %Channel{}

    socket
    |> assign(:page_title, "New Channel")
    |> assign(:channel, channel)
    |> assign(:form, Content.form_to_create_channel() |> to_form())
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    save_channel(socket, socket.assigns.live_action, params)
  end

  defp save_channel(socket, :edit, params) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, channel))}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp save_channel(socket, :new, params) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, channel))}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp return_path("index", _channel), do: ~p"/channels"
  defp return_path("show", channel), do: ~p"/channels/#{channel}"
end
