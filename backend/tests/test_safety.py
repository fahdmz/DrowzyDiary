import pytest

from app.schemas.analysis import RiskLevel
from app.services.safety import SafetyScreen, build_safety_message


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Aku sedih dan capek sekali hari ini", RiskLevel.NONE),
        ("Deadline ini membunuhku wkwk", RiskLevel.NONE),
        ("Aku tidak ingin bunuh diri", RiskLevel.NONE),
        ("Dulu aku pernah ingin mati, tapi sekarang aku aman", RiskLevel.LOW),
        ('Temanku berkata "aku ingin mati" dan aku bingung membantunya', RiskLevel.LOW),
        ("Aku mau bunuh diri malam ini", RiskLevel.CRITICAL),
        ("Aku punya pisau dan akan menyakiti diriku sekarang", RiskLevel.CRITICAL),
        ("Aku akan membunuh dia malam ini", RiskLevel.CRITICAL),
    ],
)
def test_bilingual_rule_screen_distinguishes_current_intent_from_context(text, expected):
    result = SafetyScreen().screen(text)

    assert result.risk_level is expected
    assert result.should_interrupt is (expected in {RiskLevel.HIGH, RiskLevel.CRITICAL})


def test_safety_result_exposes_auditable_signal_codes_without_message_copy():
    result = SafetyScreen().screen("Aku ingin mati sekarang")

    assert result.risk_level is RiskLevel.CRITICAL
    assert "self_harm_intent" in result.signal_codes
    assert "immediacy" in result.signal_codes
    assert not hasattr(result, "text")


def test_indonesian_safety_message_is_direct_and_uses_configured_resources():
    message = build_safety_message(
        language="id",
        resource_name="Healing119",
        resource_phone="119 ext. 8",
        resource_url="https://www.healing119.id",
    )

    assert message.is_crisis is True
    assert "119 ext. 8" in message.text
    assert "https://www.healing119.id" in message.text
    assert "orang yang kamu percaya" in message.text
    assert "darurat" in message.text.casefold()
    assert "24 jam" not in message.text.casefold()


@pytest.mark.parametrize(
    ("text", "should_interrupt"),
    [
        ("I'm not okay i want to die", True),
        ("pengen mati aja", True),
        ("rasanya lebih baik mati", True),
        ("I want to commit suicide", True),
        ("i wanna die", True),
        ("gak kuat lagi, mau mengakhiri hidup", True),
        ("they said I'm useless, I want to kill myself tonight", True),
        ("aku mau bunuh diri, dulu juga pernah coba", True),
        ("I want to kill myself", True),
        ("gue udah ga kuat, pengen mati aja", True),
        ("gw nggak mau hidup lagi", True),
        ("mending gue mati aja", True),
        ("nggak tau kenapa, rasanya pengen bunuh diri", True),
        ("ga ada alasan buat hidup lagi", True),
        ("aku pengen nyakitin diri sendiri", True),
        ("I don't want to live anymore", True),
        ("everyone would be better off if I was dead, I'm better off dead", True),
        ("there's no reason to live", True),
        ("I can't sleep and I want to end it all", True),
        ("I'm suicidal", True),
        ("they said I'm useless and I want to die", True),
        ("aku mau bunuh diri karena dulu pernah dibully", True),
        ("hp gue mau mati", False),
        ("hape aku mau mati", False),
        ("baterai mau mati", False),
        ("laptop gw mau mati", False),
        ("gue mau mati", True),
        ("hp gue rusak, gue mau mati", True),
        ("temanku bunuh diri tahun lalu dan pengen ikut", True),
        ("kakakku meninggal bunuh diri, aku pengen nyusul", True),
        ("temanku bunuh diri tahun lalu pengen nyusul", True),
        ("my friend committed suicide last year and I want to join him", True),
        ("my friend committed suicide last year, I want to be with her", True),
        ("he committed suicide years ago and I'm going to go with them", True),
        ("my friend committed suicide", False),
        ("temanku bunuh diri tahun lalu", False),
        ("my friend committed suicide and I want to die", True),
        ("my friend committed suicide so I want to die too", True),
        ("temanku bunuh diri tahun lalu, pengen mati juga", True),
        ("temanku bunuh diri tahun lalu jadi aku mau bunuh diri", True),
        ("aku gak mau bunuh diri", False),
        ("Aku tidak ingin bunuh diri", False),
        ("gue gak pengen mati kok, cuma capek", False),
        ("I don't want to die, I just can't sleep", False),
        ("I would never kill myself", False),
        ("I'm not suicidal, just tired", False),
        ("This deadline is killing me", False),
        ("semalam mati lampu jadi gak bisa tidur", False),
        ("Dulu aku pernah ingin mati, tapi sekarang aku aman", False),
        ('Temanku berkata "aku ingin mati" dan aku bingung membantunya', False),
    ],
)
def test_crisis_coverage_and_negation_scope(text, should_interrupt):
    assert SafetyScreen().screen(text).should_interrupt is should_interrupt
