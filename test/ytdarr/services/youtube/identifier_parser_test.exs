defmodule Ytdarr.Services.YouTube.IdentifierParserTest do
  use ExUnit.Case, async: true

  alias Ytdarr.Services.YouTube.IdentifierParser

  describe "parse/1 with raw handles" do
    test "parses @handle" do
      assert {:handle, "@dirty-civilian"} = IdentifierParser.parse("@dirty-civilian")
    end

    test "parses @handle with leading/trailing whitespace" do
      assert {:handle, "@dirty-civilian"} = IdentifierParser.parse("  @dirty-civilian  ")
    end

    test "rejects bare @ with no name" do
      assert {:error, :unrecognized} = IdentifierParser.parse("@")
    end
  end

  describe "parse/1 with raw channel IDs" do
    test "parses UC-prefixed channel ID" do
      assert {:channel_id, "UCsXVk37bltHxD1rDPwtNM8Q"} =
               IdentifierParser.parse("UCsXVk37bltHxD1rDPwtNM8Q")
    end

    test "parses UC-prefixed ID with whitespace" do
      assert {:channel_id, "UCsXVk37bltHxD1rDPwtNM8Q"} =
               IdentifierParser.parse("  UCsXVk37bltHxD1rDPwtNM8Q  ")
    end
  end

  describe "parse/1 with youtube.com/@handle URLs" do
    test "parses https://www.youtube.com/@handle" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("https://www.youtube.com/@dirty-civilian")
    end

    test "parses https://youtube.com/@handle" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("https://youtube.com/@dirty-civilian")
    end

    test "parses http://youtube.com/@handle" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("http://youtube.com/@dirty-civilian")
    end

    test "parses youtube.com/@handle without scheme" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("youtube.com/@dirty-civilian")
    end

    test "parses m.youtube.com/@handle (mobile)" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("https://m.youtube.com/@dirty-civilian")
    end

    test "parses @handle URL with /videos trailing segment" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("https://www.youtube.com/@dirty-civilian/videos")
    end

    test "parses @handle URL with /shorts trailing segment" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("https://www.youtube.com/@dirty-civilian/shorts")
    end

    test "parses @handle URL with /streams trailing segment" do
      assert {:handle, "@dirty-civilian"} =
               IdentifierParser.parse("https://www.youtube.com/@dirty-civilian/streams")
    end
  end

  describe "parse/1 with youtube.com/channel/ URLs" do
    test "parses channel URL with UC prefix" do
      assert {:channel_id, "UCsXVk37bltHxD1rDPwtNM8Q"} =
               IdentifierParser.parse("https://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q")
    end

    test "parses channel URL with trailing /videos" do
      assert {:channel_id, "UCsXVk37bltHxD1rDPwtNM8Q"} =
               IdentifierParser.parse(
                 "https://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q/videos"
               )
    end

    test "parses channel URL with trailing /featured" do
      assert {:channel_id, "UCsXVk37bltHxD1rDPwtNM8Q"} =
               IdentifierParser.parse(
                 "https://www.youtube.com/channel/UCsXVk37bltHxD1rDPwtNM8Q/featured"
               )
    end

    test "rejects channel URL without UC prefix" do
      assert {:error, :unrecognized} =
               IdentifierParser.parse("https://www.youtube.com/channel/notavalidid")
    end
  end

  describe "parse/1 with legacy youtube.com/c/ URLs" do
    test "parses /c/ChannelName as handle" do
      assert {:handle, "@ChannelName"} =
               IdentifierParser.parse("https://www.youtube.com/c/ChannelName")
    end
  end

  describe "parse/1 with legacy youtube.com/user/ URLs" do
    test "parses /user/Username as username" do
      assert {:username, "SomeUser"} =
               IdentifierParser.parse("https://www.youtube.com/user/SomeUser")
    end
  end

  describe "parse/1 with empty/nil/invalid input" do
    test "returns error for nil" do
      assert {:error, :empty_input} = IdentifierParser.parse(nil)
    end

    test "returns error for empty string" do
      assert {:error, :empty_input} = IdentifierParser.parse("")
    end

    test "returns error for whitespace-only string" do
      assert {:error, :empty_input} = IdentifierParser.parse("   ")
    end

    test "returns error for unrecognized input" do
      assert {:error, :unrecognized} = IdentifierParser.parse("just some random text")
    end

    test "returns error for non-YouTube URL" do
      assert {:error, :unrecognized} =
               IdentifierParser.parse("https://example.com/@something")
    end

    test "returns error for YouTube URL with no matching path" do
      assert {:error, :unrecognized} =
               IdentifierParser.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    end
  end
end
