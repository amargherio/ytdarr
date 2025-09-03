defmodule YtdarrWeb.Router do
  use YtdarrWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YtdarrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", YtdarrWeb do
    pipe_through :browser
    get "/", PageController, :home

    live "/dashboard", DashboardLive.Index, :index

    # Channel management
    live "/channels/add", ChannelLive.Add, :add
    live "/channels", ChannelLive.Index, :index
    live "/channels/new", ChannelLive.Form, :new
    live "/channels/:id/edit", ChannelLive.Form, :edit
    live "/channels/:id", ChannelLive.Show, :show

    # Oban Web dashboard (consider adding auth in production)
    forward "/oban", Oban.Web.Router
  end

  # Other scopes may use custom stacks.
  # scope "/api", YtdarrWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ytdarr, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: YtdarrWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
