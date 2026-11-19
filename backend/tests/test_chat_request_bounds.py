import pytest
from pydantic import ValidationError

from app.schemas.chat import SendMessageRequest, StartSessionRequest


def test_message_text_accepts_up_to_2000_characters():
    assert len(SendMessageRequest(session_id="s", text="a" * 2000).text) == 2000


def test_message_text_rejects_over_2000_characters():
    with pytest.raises(ValidationError):
        SendMessageRequest(session_id="s", text="a" * 2001)


@pytest.mark.parametrize("text", ["", "   ", "\n\t"])
def test_message_text_rejects_blank_after_stripping(text):
    with pytest.raises(ValidationError):
        SendMessageRequest(session_id="s", text=text)


def test_message_text_is_stripped():
    assert SendMessageRequest(session_id="s", text="  hi  ").text == "hi"


@pytest.mark.parametrize("offset", [-720, 0, 420, 840])
def test_timezone_offset_accepts_real_world_range(offset):
    assert StartSessionRequest(checkin_mode="night", timezone_offset_minutes=offset)


@pytest.mark.parametrize("offset", [-721, 841])
def test_timezone_offset_rejects_out_of_range(offset):
    with pytest.raises(ValidationError):
        StartSessionRequest(checkin_mode="night", timezone_offset_minutes=offset)
