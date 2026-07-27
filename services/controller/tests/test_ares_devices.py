import api.ares_devices as devices


def test_device_status_defaults_to_primary_with_continuity_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("ARES_CONTINUITY_DIR", str(tmp_path))
    monkeypatch.delenv("ARES_ROLE", raising=False)
    monkeypatch.setattr(devices, "_tailscale_ip", lambda: "100.64.0.10")
    monkeypatch.setattr(devices, "_local_lan_ip", lambda: "192.168.1.22")

    status = devices.device_status({"ares_device_id": "mac-studio", "ares_ai_id": "jarvis"})

    assert status["role"] == "primary"
    assert status["is_primary"] is True
    assert status["ai_id"] == "jarvis"
    assert status["device"]["device_id"] == "mac-studio"
    assert status["primary"]["reachable"] is True
    assert status["registry_path"] == str(tmp_path / "devices.yaml")


def test_device_status_can_join_existing_primary(tmp_path, monkeypatch):
    monkeypatch.setenv("ARES_CONTINUITY_DIR", str(tmp_path))
    monkeypatch.setattr(devices, "_tailscale_ip", lambda: "")
    monkeypatch.setattr(devices, "_local_lan_ip", lambda: "")
    monkeypatch.setattr(devices, "_primary_reachable", lambda url: url == "http://100.64.0.1:8787")

    status = devices.device_status({
        "ares_role": "device",
        "ares_device_id": "macbook-pro",
        "ares_ai_id": "jarvis",
        "ares_primary_url": "http://100.64.0.1:8787",
        "ares_primary_device_id": "mac-studio",
    })

    assert status["role"] == "device"
    assert status["is_primary"] is False
    assert status["primary"]["device_id"] == "mac-studio"
    assert status["primary"]["reachable"] is True


def test_register_device_writes_registry(tmp_path, monkeypatch):
    monkeypatch.setenv("ARES_CONTINUITY_DIR", str(tmp_path))
    monkeypatch.setattr(devices, "_tailscale_ip", lambda: "")
    monkeypatch.setattr(devices, "_local_lan_ip", lambda: "")

    result = devices.register_device(config={
        "ares_role": "primary",
        "ares_device_id": "mac-studio",
        "ares_ai_id": "jarvis",
    })

    assert result["ok"] is True
    assert result["registry"]["primary_device_id"] == "mac-studio"
    assert "mac-studio" in result["registry"]["devices"]
    assert (tmp_path / "devices.yaml").exists()


def test_normalize_config_update_promotes_primary_device_id():
    updates = devices.normalize_config_update({
        "role": "primary",
        "device_id": "Mac Studio",
        "ai_id": "Jarvis",
    })

    assert updates["ares_role"] == "primary"
    assert updates["ares_device_id"] == "mac-studio"
    assert updates["ares_ai_id"] == "jarvis"
    assert updates["ares_primary_device_id"] == "mac-studio"
