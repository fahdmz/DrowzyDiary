import pytest

from app.config import Settings


def test_jwks_urls_are_derived_from_supabase_url(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co/")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "server-key")

    settings = Settings()

    assert settings.supabase_auth_issuer == "https://project-ref.supabase.co/auth/v1"
    assert settings.supabase_jwks_url == (
        "https://project-ref.supabase.co/auth/v1/.well-known/jwks.json"
    )
    settings.validate()


def test_legacy_jwt_secret_is_not_required(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "server-key")
    monkeypatch.delenv("SUPABASE_JWT_SECRET", raising=False)

    Settings().validate()


@pytest.mark.parametrize("value", ["0", "601"])
def test_invalid_jwks_cache_seconds_fails_fast(
    monkeypatch: pytest.MonkeyPatch,
    value: str,
) -> None:
    monkeypatch.setenv("SUPABASE_JWKS_CACHE_SECONDS", value)

    with pytest.raises(RuntimeError):
        Settings()


def test_secret_key_is_preferred_over_legacy_service_role_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_new")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "legacy-key")

    assert Settings().supabase_secret_key == "sb_secret_new"


def test_legacy_service_role_key_is_used_as_fallback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co")
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "legacy-key")

    settings = Settings()
    settings.validate()
    assert settings.supabase_secret_key == "legacy-key"
