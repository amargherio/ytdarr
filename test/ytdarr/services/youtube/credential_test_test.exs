defmodule Ytdarr.Services.YouTube.CredentialTest do
  @moduledoc """
  Tests for YouTube credential validation via `Client.test_credential/2`.

  All tests use an injected Req plug client to avoid real network calls.
  """

  use ExUnit.Case, async: true

  alias Ytdarr.Services.YouTube.Client
  alias Ytdarr.YouTubeMocks

  # Minimal Req plug that returns a canned response.
  defmodule StubPlug do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, opts) do
      {status, body} = Keyword.fetch!(opts, :response).()

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end
  end

  defp stub_client(response_fn) do
    Req.new(plug: {StubPlug, response: response_fn})
  end

  describe "test_credential/2" do
    test "returns {:error, :empty_key} for nil key" do
      assert {:error, :empty_key} = Client.test_credential(nil)
    end

    test "returns {:error, :empty_key} for empty string key" do
      assert {:error, :empty_key} = Client.test_credential("")
    end

    test "returns {:ok, :valid} when API responds with 200" do
      client =
        stub_client(fn ->
          {200,
           %{
             "kind" => "youtube#channelListResponse",
             "items" => [YouTubeMocks.channel_response("UCBR8-60-B28hp2BmDPdntcQ")]
           }}
        end)

      assert {:ok, :valid} = Client.test_credential("some_key", client: client)
    end

    test "returns {:error, :invalid_key} on 403 keyInvalid" do
      client =
        stub_client(fn ->
          {403,
           %{
             "error" => %{
               "code" => 403,
               "message" => "API key not valid",
               "errors" => [%{"reason" => "keyInvalid", "domain" => "youtube.quota"}]
             }
           }}
        end)

      assert {:error, :invalid_key} = Client.test_credential("bad_key", client: client)
    end

    test "returns {:error, :invalid_key} on 400 API key validation errors" do
      client =
        stub_client(fn ->
          {400,
           %{
             "error" => %{
               "code" => 400,
               "message" => "API key not valid. Please pass a valid API key."
             }
           }}
        end)

      assert {:error, :invalid_key} = Client.test_credential("bad_key", client: client)
    end

    test "returns {:error, :quota_exceeded} on 403 quotaExceeded" do
      client =
        stub_client(fn ->
          {403,
           %{
             "error" => %{
               "code" => 403,
               "message" => "Quota exceeded",
               "errors" => [%{"reason" => "quotaExceeded", "domain" => "youtube.quota"}]
             }
           }}
        end)

      assert {:error, :quota_exceeded} = Client.test_credential("valid_key", client: client)
    end

    test "returns {:error, {:http_error, status, _}} for unexpected status codes" do
      client =
        stub_client(fn ->
          {500, %{"error" => %{"message" => "Internal Server Error"}}}
        end)

      assert {:error, {:http_error, 500, _message}} =
               Client.test_credential("some_key", client: client)
    end

    test "returns {:error, {:http_error, 403, _}} for 403 with unknown reason" do
      client =
        stub_client(fn ->
          {403,
           %{
             "error" => %{
               "code" => 403,
               "errors" => [%{"reason" => "accessNotConfigured"}]
             }
           }}
        end)

      assert {:error, {:http_error, 403, _reason}} =
               Client.test_credential("some_key", client: client)
    end

    test "delegates to Settings.test_youtube_credential/2" do
      # Verify the Settings domain correctly delegates to Client.test_credential/2
      client =
        stub_client(fn -> {200, %{"kind" => "youtube#channelListResponse", "items" => []}} end)

      assert {:ok, :valid} = Ytdarr.Settings.test_youtube_credential("some_key", client: client)
    end

    test "Settings.test_youtube_credential returns :empty_key for blank key" do
      assert {:error, :empty_key} = Ytdarr.Settings.test_youtube_credential("")
      assert {:error, :empty_key} = Ytdarr.Settings.test_youtube_credential(nil)
    end

    test "supports the compatibility test_credentials/1 function" do
      assert {:error, :empty_key} = Client.test_credentials(nil)
    end
  end
end
