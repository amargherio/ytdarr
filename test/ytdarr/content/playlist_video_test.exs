defmodule Ytdarr.Content.PlaylistVideoTest do
  use Ytdarr.DataCase

  import Ash.Query
  import Ytdarr.ContentFixtures

  alias Ytdarr.Content
  alias Ytdarr.Content.PlaylistVideo

  describe "PlaylistVideo" do
    test "creates a playlist/video association" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      video = video_fixture(%{channel_id: channel.id})

      assert {:ok, playlist_video} =
               create_playlist_video(%{
                 playlist_id: playlist.id,
                 video_id: video.id,
                 position: 1
               })

      assert playlist_video.playlist_id == playlist.id
      assert playlist_video.video_id == video.id
      assert playlist_video.position == 1
    end

    test "enforces uniqueness on playlist_id and video_id" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      video = video_fixture(%{channel_id: channel.id})
      attrs = %{playlist_id: playlist.id, video_id: video.id, position: 2}

      assert {:ok, _playlist_video} = create_playlist_video(attrs)
      assert {:error, %Ash.Error.Invalid{}} = create_playlist_video(attrs)

      matches =
        PlaylistVideo
        |> filter(playlist_id == ^playlist.id and video_id == ^video.id)
        |> Ash.read!(domain: Content)

      assert length(matches) == 1
    end

    test "create keeps an explicitly assigned id" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      video = video_fixture(%{channel_id: channel.id})
      explicit_id = System.unique_integer([:positive])

      assert {:ok, pv} =
               PlaylistVideo
               |> Ash.Changeset.for_create(:create, %{
                 playlist_id: playlist.id,
                 video_id: video.id,
                 position: 0
               })
               |> Ash.Changeset.force_change_attribute(:id, explicit_id)
               |> Ash.create(domain: Content)

      assert pv.id == explicit_id
    end

    test "upsert updates position when (playlist_id, video_id) already exists" do
      channel = channel_fixture()
      playlist = playlist_fixture(%{channel_id: channel.id})
      video = video_fixture(%{channel_id: channel.id})
      attrs = %{playlist_id: playlist.id, video_id: video.id, position: 1}

      assert {:ok, first} = upsert_playlist_video(attrs)
      assert {:ok, second} = upsert_playlist_video(%{attrs | position: 5})

      assert first.id == second.id
      assert second.position == 5
    end
  end

  defp create_playlist_video(attrs) do
    PlaylistVideo
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(domain: Content)
  end

  defp upsert_playlist_video(attrs) do
    PlaylistVideo
    |> Ash.Changeset.for_create(:upsert, attrs)
    |> Ash.create(domain: Content)
  end
end
