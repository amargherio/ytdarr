defmodule Ytdarr.Content.VideoTest do
  use Ytdarr.DataCase

  import Ytdarr.ContentFixtures

  alias Ash.Error.Changes.Required
  alias Ytdarr.Content

  describe "create_video/2" do
    test "creates with valid attributes" do
      channel = channel_fixture()
      attrs = video_attrs()

      assert {:ok, video} = Content.create_video(channel.id, attrs)
      assert video.channel_id == channel.id
      assert video.title == attrs.title
      assert video.external_id == attrs.external_id
      assert video.url == attrs.url
    end

    test "fails when required attributes or channel_id are nil" do
      channel = channel_fixture()
      attrs = video_attrs()

      for field <- [:title, :external_id, :url] do
        result = Content.create_video(channel.id, Map.put(attrs, field, nil))
        assert_required_error(result, field, :attribute)
      end

      result = Content.create_video(nil, attrs)
      assert_required_error(result, :channel_id, :argument)
    end
  end

  describe "SetDiscoveredFields" do
    test "sets discovered_at and uploads position when discovered_from is uploads" do
      channel = channel_fixture()

      assert {:ok, video} =
               Content.create_video(
                 channel.id,
                 video_attrs(%{
                   discovered_from: "uploads"
                 })
               )

      assert %DateTime{} = video.discovered_at
      assert video.position_in_uploads == 0
    end

    test "sets discovered_at without uploads position for other discovery sources" do
      channel = channel_fixture()

      assert {:ok, video} =
               Content.create_video(
                 channel.id,
                 video_attrs(%{
                   discovered_from: "playlist:abc123"
                 })
               )

      assert %DateTime{} = video.discovered_at
      assert is_nil(video.position_in_uploads)
    end
  end

  describe "mark_video_downloaded/2" do
    test "marks a video as downloaded" do
      video = video_fixture()

      assert {:ok, updated_video} =
               Content.mark_video_downloaded(video, %{
                 download_path: "/downloads/test-video.mp4",
                 file_size: 123_456,
                 download_quality: "1080p"
               })

      assert updated_video.is_downloaded
      assert updated_video.download_state == :downloaded
      assert updated_video.download_path == "/downloads/test-video.mp4"
      assert updated_video.file_size == 123_456
      assert updated_video.download_quality == "1080p"
      assert %DateTime{} = updated_video.downloaded_at
    end
  end

  describe "download_state transitions" do
    test "accepts all supported download states" do
      video = video_fixture()

      Enum.reduce([:available, :downloading, :downloaded, :missing], video, fn state,
                                                                               current_video ->
        assert {:ok, updated_video} =
                 Content.update_video(current_video, %{download_state: state})

        assert updated_video.download_state == state
        updated_video
      end)
    end
  end

  defp video_attrs(overrides \\ %{}) do
    unique_id = System.unique_integer([:positive])

    Enum.into(overrides, %{
      title: "Test Video #{unique_id}",
      external_id: "video-#{unique_id}",
      url: "https://www.youtube.com/watch?v=video#{unique_id}",
      description: "Video description",
      upload_date: Date.utc_today(),
      duration: 600
    })
  end

  defp assert_required_error({:error, %Ash.Error.Invalid{errors: errors}}, field, type) do
    assert Enum.any?(errors, fn
             %Required{field: ^field, type: ^type} -> true
             _ -> false
           end)
  end
end
