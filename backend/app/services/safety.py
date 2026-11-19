"""Deterministic bilingual safety screening before any model call.

This is a conservative routing aid, not a clinical assessment. Only current,
first-person self-harm intent or an imminent threat interrupts normal chat.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Literal

from app.schemas.analysis import RiskLevel

Language = Literal["en", "id"]

_ID_NEGATION = r"(?:tidak|nggak|enggak|ngga|engga|gak|ga|gk|tak|kagak)"
_ID_WANT = r"(?:ingin|mau|pengen|pengin|pingin|kepengen)"
_SELF_HARM_PATTERNS = (
    r"\bbunuh diri\b",
    r"\bgantung diri\b",
    r"\b(?:aku|saya|gue|gw|gua) (?:pernah )?(?:ingin|mau|pengen|akan) mati\b",
    rf"\b{_ID_WANT} mati\b(?! (?:lampu|listrik|gaya)\b)",
    r"\b(?:lebih baik|mending|mendingan)(?: (?:aku|saya|gue|gw|gua))? mati\b",
    r"\b(?:mengakhiri|akhiri|ngakhirin) hidup",
    rf"\b{_ID_NEGATION} (?:{_ID_WANT}|kuat) hidup\b",
    rf"\b{_ID_NEGATION} ada (?:alasan|gunanya) (?:untuk |buat )?hidup\b",
    r"\b(?:aku|saya|gue|gw) (?:akan |mau |ingin )?(?:menyakiti|melukai) diri\b",
    r"\bkill myself\b",
    r"\bsuicid(?:e|al)\b",
    r"\b(?:i )?(?:want|wanna|plan|going|gonna) (?:to )?die\b",
    r"\b(?:don't|do not|dont) want to (?:live|be alive|exist)\b",
    r"\bno reason to live\b",
    r"\bnothing to live for\b",
    r"\bbetter off dead\b",
    r"\bbetter off without me\b",
    r"\bend (?:my life|it all)\b",
    r"\btake my (?:own )?life\b",
    r"\bhurt myself\b",
    r"\bself[- ]harm\b",
    r"\b(?:menyakiti|melukai|nyakitin|ngelukain) diri(?:ku)?\b",
)
_VIOLENCE_PATTERNS = (
    r"\b(?:aku|saya|gue|gw) akan membunuh (?:dia|mereka|kamu)\b",
    r"\bi (?:will|am going to) kill (?:him|her|them|you)\b",
)
_IMMEDIACY_PATTERN = re.compile(
    r"\b(?:sekarang|malam ini|hari ini|sebentar lagi|now|tonight|today|soon)\b"
)
_MEANS_PATTERN = re.compile(
    r"\b(?:pisau|pistol|senjata|tali|racun|knife|gun|weapon|rope|poison)\b"
)
_CLAUSE_BREAK_PATTERN = re.compile(
    r"\b(?:tapi|tetapi|namun|but|however)\b|[.!?]+|,(?=\s*(?:sekarang|now)\b)"
)
_SEGMENT_BREAK_PATTERN = re.compile(
    r",(?!\s*[\"'“”])|\b(?:dan|and)\b(?=\s+(?:i|aku|saya|gue|gw)\b)"
)
_NEGATIONS = frozenset(
    {
        "tidak", "nggak", "enggak", "ngga", "engga", "gak", "ga", "gk", "tak",
        "kagak", "bukan", "no", "not", "never", "dont", "wont", "cant", "didnt",
    }
)
# Words that may sit between a negation and the intent it negates.
_INTENT_FILLERS = frozenset(
    {
        "aku", "saya", "gue", "gw", "gua", "mau", "ingin", "pengen", "pengin",
        "pingin", "kepengen", "akan", "bakal", "pernah", "sampai", "sampe",
        "berniat", "niat", "coba", "nyoba", "mencoba", "untuk", "buat", "sih",
        "kok", "juga", "i", "m", "am", "do", "would", "will", "ll", "d", "ever",
        "even", "really", "want", "wanna", "to", "going", "gonna", "plan",
        "planning", "try", "trying", "ca", "wo", "did",
    }
)
_HISTORICAL_MARKERS = (
    "dulu",
    "pernah",
    "waktu itu",
    "in the past",
    "used to",
    "previously",
)
_CURRENT_SAFE_MARKERS = (
    "sekarang aku aman",
    "sekarang saya aman",
    "aku sudah aman",
    "i am safe now",
    "i'm safe now",
)
_CURRENT_TIME_MARKERS = ("masih", "sekarang", "still", "now")
_DEVICE_SUBJECT_PATTERN = re.compile(
    r"^(?:(?:si|itu) )?(?:hp|hape|handphone|ponsel|baterai|batre|laptop|charger)"
    r"(?: (?:aku|saya|gue|gw|gua))?$"
)
_FIRST_PERSON_PATTERN = re.compile(
    r"\b(?:i|me|myself|aku|saya|gue|gw|gua|diriku)\b"
)
_THIRD_PERSON_SUBJECT_PATTERN = re.compile(
    r"\b(?:my (?:friend|brother|sister|dad|mom|father|mother|cousin|colleague|classmate)"
    r"|he|she|they|temanku|teman saya|dia|kakakku|adikku|ayahku|ibuku|sepupuku)\b"
)
_PAST_EVENT_PATTERN = re.compile(
    r"\b(?:committed|died by|killed (?:himself|herself|themself)|last year|years ago"
    r"|tahun lalu|bulan lalu|tahun kemarin)\b"
)
_JOIN_PATTERN = re.compile(
    rf"\b{_ID_WANT} (?:ikut|nyusul|menyusul)\b"
    r"|\b(?:nyusul|menyusul|ikut) (?:dia|nya|mereka)\b"
    r"|\b(?:want|wanna|going|gonna|plan)(?: to)? (?:join|follow|be with|go with) (?:him|her|them)\b"
    r"|\bgo with (?:him|her|them)\b"
)
_THIRD_PERSON_MARKERS = (
    "temanku berkata",
    "teman saya berkata",
    "dia berkata",
    "temanku bilang",
    "dia bilang",
    "katanya",
    "my friend said",
    "they said",
    "he said",
    "she said",
)
_RISK_RANK = {
    RiskLevel.NONE: 0,
    RiskLevel.LOW: 1,
    RiskLevel.MEDIUM: 2,
    RiskLevel.HIGH: 3,
    RiskLevel.CRITICAL: 4,
}


@dataclass(frozen=True)
class SafetyResult:
    risk_level: RiskLevel
    signal_codes: tuple[str, ...]

    @property
    def should_interrupt(self) -> bool:
        return self.risk_level in {RiskLevel.HIGH, RiskLevel.CRITICAL}


@dataclass(frozen=True)
class SafetyMessage:
    text: str
    is_crisis: bool = True


class SafetyScreen:
    def screen(self, text: str) -> SafetyResult:
        normalized = unicodedata.normalize("NFKC", text).casefold().replace("’", "'")
        clauses = [
            clause.strip(" ,;:\t\n\r\"'")
            for clause in _CLAUSE_BREAK_PATTERN.split(normalized)
            if clause.strip(" ,;:\t\n\r\"'")
        ]
        results = [_screen_clause(clause) for clause in clauses or [normalized]]
        return max(results, key=lambda result: _RISK_RANK[result.risk_level])


def _screen_clause(text: str) -> SafetyResult:
    segments = [
        segment.strip(" ,;:\t\n\r\"'")
        for segment in _SEGMENT_BREAK_PATTERN.split(text)
        if segment.strip(" ,;:\t\n\r\"'")
    ] or [text]
    join = bool(_JOIN_PATTERN.search(text))
    self_harm = max(_intent_state(s, _SELF_HARM_PATTERNS, join) for s in segments)
    violence = max(_intent_state(s, _VIOLENCE_PATTERNS, join) for s in segments)
    if not self_harm and not violence:
        return SafetyResult(RiskLevel.NONE, ())

    signals: list[str] = []
    if self_harm:
        signals.append("self_harm_intent")
    if violence:
        signals.append("violence_intent")

    if _CURRENT not in (self_harm, violence):
        signals.append("contextual_or_historical")
        return SafetyResult(RiskLevel.LOW, tuple(signals))

    if _IMMEDIACY_PATTERN.search(text):
        signals.append("immediacy")
    if _MEANS_PATTERN.search(text):
        signals.append("means_access")

    risk = (
        RiskLevel.CRITICAL
        if "immediacy" in signals or "means_access" in signals
        else RiskLevel.HIGH
    )
    return SafetyResult(risk, tuple(signals))


def build_safety_message(
    *,
    language: Language,
    resource_name: str,
    resource_phone: str,
    resource_url: str,
) -> SafetyMessage:
    if language == "id":
        text = (
            "Terima kasih sudah memberitahuku. Aku khawatir kamu mungkin berada "
            "dalam bahaya sekarang. Tolong jauhkan benda atau obat yang bisa "
            "melukaimu, hubungi orang yang kamu percaya agar menemanimu, dan "
            "hubungi layanan darurat 119 bila bahayanya segera. Kamu juga dapat "
            f"menghubungi {resource_name} di {resource_phone} atau {resource_url}."
        )
    else:
        text = (
            "Thank you for telling me. I'm concerned you may be in immediate "
            "danger. Move away from anything you could use to hurt yourself, ask "
            "someone you trust to stay with you, and call emergency service 119 "
            f"if the danger is immediate. You can also contact {resource_name} at "
            f"{resource_phone} or {resource_url}."
        )
    return SafetyMessage(text=text)


_NO_INTENT, _CONTEXTUAL, _CURRENT = 0, 1, 2


def _intent_state(text: str, patterns: tuple[str, ...], join: bool = False) -> int:
    state = _NO_INTENT
    safe_now = any(marker in text for marker in _CURRENT_SAFE_MARKERS)
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            if _is_negated(text[: match.start()]):
                continue
            if _is_device_subject(text[: match.start()]):
                continue
            if (
                safe_now
                or (not join and _is_third_person_past(text))
                or _is_contextual(text[: match.end()])
            ):
                state = _CONTEXTUAL
                continue
            return _CURRENT
    return state


def _is_device_subject(preceding: str) -> bool:
    return bool(_DEVICE_SUBJECT_PATTERN.match(preceding.strip()))


def _is_third_person_past(text: str) -> bool:
    return bool(
        _THIRD_PERSON_SUBJECT_PATTERN.search(text)
        and _PAST_EVENT_PATTERN.search(text)
        and not _FIRST_PERSON_PATTERN.search(text)
    )


def _is_negated(preceding: str) -> bool:
    tokens = re.findall(r"\b\w+\b", re.sub(r"n't\b", " not", preceding))
    for token in reversed(tokens):
        if token in _NEGATIONS:
            return True
        if token not in _INTENT_FILLERS:
            return False
    return False


def _is_contextual(text: str) -> bool:
    if any(marker in text for marker in _THIRD_PERSON_MARKERS):
        return True
    last_historical = _last_marker_end(text, _HISTORICAL_MARKERS)
    return last_historical > _last_marker_end(text, _CURRENT_TIME_MARKERS)


def _last_marker_end(text: str, markers: tuple[str, ...]) -> int:
    ends = [m.end() for marker in markers for m in re.finditer(rf"\b{marker}\b", text)]
    return max(ends, default=-1)
