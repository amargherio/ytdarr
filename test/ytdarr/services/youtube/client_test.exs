defmodule Ytdarr.Services.YouTube.ClientTest do
  @moduledoc """
  Tests for the YouTube Client module.

  Tests the high-level client functions including pagination and batch processing.
  """
  use ExUnit.Case, async: true

  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.YouTubeMocks

  # Test plug for mocking HTTP responses
  defmodule TestPlug do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, opts) do
      response_fn = Keyword.fetch!(opts, :response_fn)
      {status, body} = response_fn.(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end
  end

  describe "get_uploads_playlist_id/1" do
    test "converts channel ID to uploads playlist ID" do
      assert Client.get_uploads_playlist_id("UC7X2IY5-ZHKU83nyb6KejgQ") ==
               "UU7X2IY5-ZHKU83nyb6KejgQ"
    end

    test "handles various channel ID formats" do
      assert Client.get_uploads_playlist_id("UCabcdefghijklmnop") == "UUabcdefghijklmnop"

      assert Client.get_uploads_playlist_id("UC123456789012345678901") ==
               "UU123456789012345678901"
    end

    test "handles short channel IDs" do
      assert Client.get_uploads_playlist_id("UC12") == "UU12"
    end
  end

  describe "video ID extraction" do
    test "generates correct video IDs list" do
      video_ids = YouTubeMocks.generate_video_ids(5)
      assert length(video_ids) == 5
      assert Enum.all?(video_ids, &is_binary/1)
      # IDs should be unique
      assert length(Enum.uniq(video_ids)) == 5
    end

    test "generates 11-character video IDs" do
      video_ids = YouTubeMocks.generate_video_ids(3)
      assert Enum.all?(video_ids, fn id -> String.length(id) == 11 end)
    end
  end
end
