"""Fixed opening greeting for each check-in type."""

from typing import Literal

CheckinMode = Literal["night", "morning"]
Language = Literal["en", "id"]

GREETINGS: dict[CheckinMode, dict[Language, str]] = {
    "night": {
        "en": "Hi, I'm here. What's on your mind tonight?",
        "id": "Hai, aku di sini. Apa yang sedang kamu pikirkan malam ini?",
    },
    "morning": {
        "en": "Good morning. How did you sleep?",
        "id": "Selamat pagi. Bagaimana tidurmu semalam?",
    },
}


def greeting_for(mode: CheckinMode, language: Language) -> str:
    lang = language if language in ("en", "id") else "en"
    return GREETINGS[mode][lang]

