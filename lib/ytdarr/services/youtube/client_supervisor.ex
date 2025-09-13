defmodule Ytdarr.Services.YouTube.ClientSupervisor do
  @base_url "https://www.googleapis.com/youtube/v3"
  @api_key Application.compile_env(:ytdarr, :youtube_api_key) || "12345testkey"

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_client do
    case Registry.lookup(Ytdarr.Services.Registry, :youtube_client) do
      [{pid, client}] when is_pid(pid) -> client
      [] -> create_client()
    end
  end

  def init(_opts) do
    client = create_client()
    Registry.register(Ytdarr.Services.Registry, :youtube_client, client)
    {:ok, client}
  end

  defp create_client do
    Req.new(
      base_url: @base_url,
      headers: %{
        accept: "application/json",
        user_agent: "Ytdarr/1.0"
      },
      auth: {:bearer, @api_key || ""},
      finch: Ytdarr.Finch
      # adding in logging for non-prod or debug level output
      #request_steps: request_steps(),
      #response_steps: response_steps()
    )
  end

  # defp request_steps do
  #   steps = []

  #   if Application.get_env(:ytdarr, :log_youtube_requests, false) || Mix.env() != :prod do
  #     [Req.Steps.log_request | steps]
  #   else
  #     steps
  #   end
  # end

  # defp response_steps do
  #   steps = []

  #   if Application.get_env(:ytdarr, :log_youtube_requests, false) || Mix.env() != :prod do
  #     [Req.Steps.log_response | steps]
  #   else
  #     steps
  #   end
  # end
end
