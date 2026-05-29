defmodule Ytdarr.Content.ResolveChannelTest do
  @moduledoc """
  Tests for Content.resolve_channel/2 — resolving YouTube channels
  by handle, URL, or channel ID without using the search endpoint.
  """
  use Ytdarr.DataCase

  alias Ytdarr.Content
  alias Ytdarr.YouTubeMocks

  import Ytdarr.ContentFixtures

  # Test plug for mocking YouTube API responses
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

  defp create_test_client(response_fn) do
    Req.new(
      plug: {TestPlug, response_fn: response_fn},
      retry: false
    )
  end

  describe "resolve_channel/2 with valid handle" do
    test "resolves a new channel by @handle" do
      channel_id = "UCTestResolve123456789012"

      client =
        create_test_client(fn conn ->
          assert String.ends_with?(conn.request_path, "/channels")
          assert conn.query_string =~ "forHandle=%40dirty-civilian"
          {200, YouTubeMocks.channel_response(channel_id, title: "Dirty Civilian")}
        end)

      assert {:ok, resolved} =
               Content.resolve_channel("@dirty-civilian",
                 client: client,
                 skip_quota_tracking: true
               )

      assert resolved.name == "Dirty Civilian"
      assert resolved.external_id == channel_id
      assert resolved.platform == "YouTube"
    end

    test "resolves a new channel by full URL with handle" do
      channel_id = "UCTestResolve223456789012"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "forHandle=%40some-channel"
          {200, YouTubeMocks.channel_response(channel_id, title: "Some Channel")}
        end)

      assert {:ok, resolved} =
               Content.resolve_channel("https://www.youtube.com/@some-channel",
                 client: client,
                 skip_quota_tracking: true
               )

      assert resolved.name == "Some Channel"
      assert resolved.external_id == channel_id
    end
  end

  describe "resolve_channel/2 with channel ID" do
    test "resolves a new channel by raw channel ID" do
      channel_id = "UCTestResolve323456789012"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "id=#{channel_id}"
          {200, YouTubeMocks.channel_response(channel_id, title: "ID Channel")}
        end)

      assert {:ok, resolved} =
               Content.resolve_channel(channel_id,
                 client: client,
                 skip_quota_tracking: true
               )

      assert resolved.name == "ID Channel"
      assert resolved.external_id == channel_id
    end

    test "resolves a channel by URL with channel ID" do
      channel_id = "UCTestResolve423456789012"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "id=#{channel_id}"
          {200, YouTubeMocks.channel_response(channel_id, title: "URL Channel")}
        end)

      assert {:ok, resolved} =
               Content.resolve_channel(
                 "https://youtube.com/channel/#{channel_id}",
                 client: client,
                 skip_quota_tracking: true
               )

      assert resolved.name == "URL Channel"
    end
  end

  describe "resolve_channel/2 with legacy username" do
    test "resolves a channel by /user/ URL" do
      channel_id = "UCTestResolve523456789012"

      client =
        create_test_client(fn conn ->
          assert conn.query_string =~ "forUsername=LegacyUser"
          {200, YouTubeMocks.channel_response(channel_id, title: "Legacy User Channel")}
        end)

      assert {:ok, resolved} =
               Content.resolve_channel(
                 "https://youtube.com/user/LegacyUser",
                 client: client,
                 skip_quota_tracking: true
               )

      assert resolved.name == "Legacy User Channel"
    end
  end

  describe "resolve_channel/2 returns already_tracked" do
    test "returns already_tracked when channel exists in DB" do
      existing = channel_fixture(%{external_id: "UCExistingChannel123456789"})

      client =
        create_test_client(fn _conn ->
          {200,
           YouTubeMocks.channel_response("UCExistingChannel123456789", title: "Existing Channel")}
        end)

      assert {:already_tracked, tracked} =
               Content.resolve_channel("UCExistingChannel123456789",
                 client: client,
                 skip_quota_tracking: true
               )

      assert tracked.id == existing.id
      assert tracked.external_id == "UCExistingChannel123456789"
    end
  end

  describe "resolve_channel/2 error cases" do
    test "returns error for empty input" do
      assert {:error, :empty_input} = Content.resolve_channel("")
    end

    test "returns error for nil input" do
      assert {:error, :empty_input} = Content.resolve_channel(nil)
    end

    test "returns error for unrecognized input" do
      assert {:error, :unrecognized} = Content.resolve_channel("just random text")
    end

    test "returns error when channel not found on YouTube" do
      client =
        create_test_client(fn _conn ->
          {200,
           %{
             "kind" => "youtube#channelListResponse",
             "pageInfo" => %{"totalResults" => 0, "resultsPerPage" => 5},
             "items" => []
           }}
        end)

      assert {:error, :not_found} =
               Content.resolve_channel("UCDoesNotExist123456789012",
                 client: client,
                 skip_quota_tracking: true
               )
    end

    test "returns error on API failure" do
      client =
        create_test_client(fn _conn ->
          {403, YouTubeMocks.error_response(403, "quotaExceeded")}
        end)

      assert {:error, {:http_error, 403, _body}} =
               Content.resolve_channel("UCApiError123456789012345",
                 client: client,
                 skip_quota_tracking: true
               )
    end
  end
end
