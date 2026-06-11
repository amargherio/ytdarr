defmodule Ytdarr.Services.YouTube.ParserTest do
  use ExUnit.Case, async: true

  alias Ytdarr.Content
  alias Ytdarr.Services.YouTube.{Models, Parser}

  describe "create_ytdarr_channel/1" do
    test "maps every field from a Models.Channel struct" do
      yt = %Models.Channel{
        id: "UCParseChannel",
        title: "Parse Channel",
        description: "described",
        url: "https://www.youtube.com/@parsechannel",
        thumbnail_url: "https://example.com/avatar.jpg",
        banner_url: "https://example.com/banner.jpg",
        custom_url: "@parsechannel",
        uploads_playlist_id: "UUParseChannel"
      }

      channel = Parser.create_ytdarr_channel(yt)

      assert %Content.Channel{} = channel
      assert channel.external_id == "UCParseChannel"
      assert channel.name == "Parse Channel"
      assert channel.url == "https://www.youtube.com/@parsechannel"
      assert channel.description == "described"
      assert channel.platform == "YouTube"
      assert channel.avatar_url == "https://example.com/avatar.jpg"
      assert channel.banner_url == "https://example.com/banner.jpg"
      assert channel.platform_username == "@parsechannel"
      assert channel.uploads_playlist_id == "UUParseChannel"
      refute channel.is_monitored
      assert is_nil(channel.is_monitored_since)
      assert is_nil(channel.last_checked_at)
      assert is_nil(channel.base_path)
      assert is_nil(channel.generic_video_path)
    end
  end

  describe "create_ytdarr_playlist/2" do
    test "maps every field from a Models.Playlist struct" do
      yt = %Models.Playlist{
        id: "PLParse",
        title: "Parse Playlist",
        url: "https://www.youtube.com/playlist?list=PLParse",
        description: "described",
        video_count: 7
      }

      playlist = Parser.create_ytdarr_playlist(yt, 42)

      assert %Content.Playlist{} = playlist
      assert playlist.external_id == "PLParse"
      assert playlist.name == "Parse Playlist"
      assert playlist.url == "https://www.youtube.com/playlist?list=PLParse"
      assert playlist.description == "described"
      assert playlist.video_count == 7
      assert playlist.channel_id == 42
      refute playlist.is_monitored
      assert is_nil(playlist.last_checked_at)
    end
  end

  describe "parse_date/1" do
    test "parses ISO8601 datetimes into UTC Date" do
      assert Parser.parse_date("2025-01-15T10:00:00Z") == ~D[2025-01-15]
    end

    test "returns nil for nil, invalid, and non-binary input" do
      assert is_nil(Parser.parse_date(nil))
      assert is_nil(Parser.parse_date("not-a-date"))
      assert is_nil(Parser.parse_date(12_345))
    end
  end

  describe "parse_int/1" do
    test "parses numeric strings, returns integers as-is, nil otherwise" do
      assert Parser.parse_int("42") == 42
      assert Parser.parse_int(42) == 42
      assert is_nil(Parser.parse_int(nil))
      assert is_nil(Parser.parse_int("not-a-number"))
      assert is_nil(Parser.parse_int(:atom))
    end
  end

  describe "parse_duration/1" do
    test "parses ISO8601 durations into total seconds" do
      assert Parser.parse_duration("PT1H2M3S") == 3723
      assert Parser.parse_duration("PT5M30S") == 330
      assert Parser.parse_duration("PT45S") == 45
      assert Parser.parse_duration("PT2H15M") == 8100
      assert Parser.parse_duration("PT3H") == 10_800
    end

    test "returns nil for nil, malformed strings, and non-binary input" do
      assert is_nil(Parser.parse_duration(nil))
      assert is_nil(Parser.parse_duration("garbage"))
      assert is_nil(Parser.parse_duration(123))
    end
  end
end
