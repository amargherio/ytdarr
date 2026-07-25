defmodule Ytdarr.Imports.SafeMessageTest do
  use ExUnit.Case, async: true

  alias Ytdarr.Imports.SafeMessage

  test "maps every persisted import message to approved safe copy" do
    assert SafeMessage.for(:ffprobe_unavailable) ==
             "ffprobe is unavailable. Install ffmpeg and restart Ytdarr."

    assert SafeMessage.for(:ffprobe_timeout) == "Video inspection timed out."

    assert SafeMessage.for(:no_video_stream) ==
             "The selected file does not contain a video stream."

    assert SafeMessage.for(:source_unavailable) == "The selected file is no longer available."
    assert SafeMessage.for(:source_changed) == "The selected file changed. Select it again."

    assert SafeMessage.for(:destination_changed) ==
             "The video's metadata changed. Reopen Import and try again."

    assert SafeMessage.for(:destination_exists) ==
             "The canonical destination already exists. Remove it before importing."

    assert SafeMessage.for(:source_not_writable) ==
             "Ytdarr cannot read and move the selected file. Check its permissions."

    assert SafeMessage.for(:source_unreadable) ==
             "Ytdarr cannot read and move the selected file. Check its permissions."

    assert SafeMessage.for(:import_conflict) == "An import is already in progress for this video."

    assert SafeMessage.for(:unexpected) ==
             "Ytdarr could not import this file. Check the server logs and try again."
  end
end
