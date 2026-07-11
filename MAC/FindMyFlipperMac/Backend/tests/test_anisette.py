from findmy_gateway import anisette


def test_ensure_anisette_returns_existing_service(monkeypatch):
    monkeypatch.setattr(anisette, "anisette_is_available", lambda timeout=2.0: True)

    result = anisette.ensure_anisette_server()

    assert result.ok is True
    assert result.runtime == "existing"


def test_ensure_anisette_missing_docker_without_install_does_not_install(monkeypatch):
    monkeypatch.setattr(anisette, "anisette_is_available", lambda timeout=2.0: False)
    monkeypatch.setattr(anisette, "_which", lambda name: None)

    result = anisette.ensure_anisette_server(install_if_missing=False)

    assert result.ok is False
    assert "Docker is not installed" in result.error


def test_ensure_anisette_returns_install_error(monkeypatch):
    monkeypatch.setattr(anisette, "anisette_is_available", lambda timeout=2.0: False)
    monkeypatch.setattr(anisette, "_which", lambda name: None)
    monkeypatch.setattr(
        anisette,
        "_install_orbstack",
        lambda: anisette.AnisetteResult(ok=False, error="install failed"),
    )

    result = anisette.ensure_anisette_server(install_if_missing=True)

    assert result.ok is False
    assert result.error == "install failed"
