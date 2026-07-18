"""Import and identity tests for the route_session_list_cache extraction."""


def test_route_session_list_cache_exports():
    from api import route_session_list_cache as slc

    assert hasattr(slc, "_SESSIONS_CACHE")
    assert hasattr(slc, "_session_list_cache_key")
    assert callable(slc._session_list_cache_overlay_runtime_rows)
    assert callable(slc._session_list_cache_source_stamp)


def test_cache_module_owns_the_runtime_contract():
    from api import route_session_list_cache as slc

    assert hasattr(slc, "_session_list_cache_key")
    assert hasattr(slc, "_session_list_cache_state_db_fingerprint")
    assert callable(slc._session_list_cache_done)
    assert callable(slc.get_cached_session_list_payload)


def test_shared_cache_objects():
    from api import route_session_list_cache as slc

    assert isinstance(slc._SESSIONS_CACHE, dict)
    assert isinstance(slc._SESSIONS_CACHE_INFLIGHT, dict)
    assert hasattr(slc._SESSIONS_CACHE_LOCK, "acquire")


def test_shared_cache_state_mutation():
    from api import route_session_list_cache as slc

    key = slc._session_list_cache_key(
        active_profile="default",
        all_profiles=False,
        show_cli_sessions=False,
        show_previous_messaging_sessions=False,
        show_cron_sessions=False,
    )
    payload = {"sessions": []}
    slc._session_list_cache_clear()
    slc._session_list_cache_set(key, payload)
    try:
        shared_payload, _fresh = slc._session_list_cache_get(key, allow_stale=True)
        assert shared_payload == payload
        assert _fresh in (False, True)
    finally:
        slc._session_list_cache_clear()


def test_live_scalar_exports_follow_route_session_list_cache_state():
    from api import route_session_list_cache as slc

    before = slc._SESSIONS_CACHE_GLOBAL_INVALIDATION_VERSION
    slc._session_list_cache_clear()
    after = slc._SESSIONS_CACHE_GLOBAL_INVALIDATION_VERSION

    assert after == before + 1


def test_no_circular_import():
    import pathlib

    src = (
        pathlib.Path(__file__).parent.parent
        / "api"
        / "route_session_list_cache.py"
    ).read_text()
    for line in src.splitlines():
        if line.startswith("from api.routes import") or line.startswith("import api.routes"):
            raise AssertionError(
                "route_session_list_cache must not import api.routes at module scope"
            )
