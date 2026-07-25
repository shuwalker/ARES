"""ARES secret values stored in the operating system credential vault."""

from __future__ import annotations


SERVICE_PREFIX = "com.ares.webui.secrets"


class SecretVaultError(RuntimeError):
    pass


def _service(profile: str | None) -> str:
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return f"{SERVICE_PREFIX}.{safe}"


def set_secret(profile: str | None, key: str, value: str) -> None:
    try:
        import keyring
        keyring.set_password(_service(profile), key, value)
    except Exception as exc:
        raise SecretVaultError(f"The operating system credential vault could not store {key}: {exc}") from exc


def get_secret(profile: str | None, key: str) -> str:
    try:
        import keyring
        value = keyring.get_password(_service(profile), key)
    except Exception as exc:
        raise SecretVaultError(f"The operating system credential vault could not read {key}: {exc}") from exc
    if value is None:
        raise SecretVaultError(f"No credential-vault value exists for {key}")
    return value


def delete_secret(profile: str | None, key: str) -> None:
    try:
        import keyring
        from keyring.errors import PasswordDeleteError
        try:
            keyring.delete_password(_service(profile), key)
        except PasswordDeleteError:
            pass
    except Exception as exc:
        raise SecretVaultError(f"The operating system credential vault could not delete {key}: {exc}") from exc
