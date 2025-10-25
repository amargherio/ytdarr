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
          <.input field={@form[:description]} type="text" label="Description" />
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
    |> assign(:form, to_form(Content.change_channel(channel)))
  end

  defp apply_action(socket, :new, _params) do
    channel = %Channel{}

    socket
    |> assign(:page_title, "New Channel")
    |> assign(:channel, channel)
    |> assign(:form, to_form(Content.change_channel(channel)))
  end

  @impl true
  def handle_event("validate", %{"channel" => channel_params}, socket) do
    changeset = Content.change_channel(socket.assigns.channel, channel_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"channel" => channel_params}, socket) do
    save_channel(socket, socket.assigns.live_action, channel_params)
  end

  defp save_channel(socket, :edit, channel_params) do
    case Content.update_channel(socket.assigns.channel, channel_params) do
      {:ok, channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, channel))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_channel(socket, :new, channel_params) do
    case Content.create_channel(channel_params) do
      {:ok, channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, channel))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _channel), do: ~p"/channels"
  defp return_path("show", channel), do: ~p"/channels/#{channel}"
end
