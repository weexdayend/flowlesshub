#!/usr/bin/env python3
"""Send sanitized FlowlessHub backup lifecycle notifications to Discord."""

from __future__ import annotations

import argparse
import http.client
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping

CREDENTIAL_NAME = "discord-webhook-url"
CREDENTIAL_MAX_BYTES = 4096
HTTP_TIMEOUT_SECONDS = 5.0
MAX_ATTEMPTS = 3
MAX_RETRY_AFTER_SECONDS = 5.0
TOTAL_BUDGET_SECONDS = 25.0
DISCORD_HOST = "discord.com"
WEBHOOK_PATH = re.compile(r"^/api/webhooks/[0-9]+/[A-Za-z0-9._-]+$")
SAFE_RESULT = re.compile(r"^[a-z0-9_-]{1,40}$")
SAFE_EXIT_CODE = re.compile(r"^(?:exited|killed|dumped|)$")
SAFE_EXIT_STATUS = re.compile(r"^[A-Za-z0-9_.-]{0,40}$")


class AlertDeliveryError(Exception):
    """A sanitized delivery or event-validation failure."""


def validate_webhook_url(value: str) -> str:
    """Accept only a Discord HTTPS incoming-webhook URL without extra query data."""
    candidate = value.strip()
    try:
        parsed = urllib.parse.urlsplit(candidate)
        port = parsed.port
    except ValueError as exc:
        raise AlertDeliveryError("invalid_webhook_url") from exc

    if (
        parsed.scheme != "https"
        or parsed.hostname != DISCORD_HOST
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
        or parsed.query
        or parsed.fragment
        or not WEBHOOK_PATH.fullmatch(parsed.path)
    ):
        raise AlertDeliveryError("invalid_webhook_url")

    return urllib.parse.urlunsplit(("https", DISCORD_HOST, parsed.path, "wait=true", ""))


def read_webhook_credential(credentials_directory: str | None = None) -> str:
    directory = credentials_directory or os.environ.get("CREDENTIALS_DIRECTORY", "")
    if not directory:
        raise AlertDeliveryError("credential_directory_unavailable")

    path = Path(directory) / CREDENTIAL_NAME
    try:
        if path.is_symlink() or not path.is_file():
            raise AlertDeliveryError("credential_file_unavailable")
        if path.stat().st_size > CREDENTIAL_MAX_BYTES:
            raise AlertDeliveryError("credential_file_invalid")
        value = path.read_text(encoding="utf-8").strip()
    except AlertDeliveryError:
        raise
    except (OSError, UnicodeError):
        raise AlertDeliveryError("credential_file_unavailable") from None

    if not value:
        raise AlertDeliveryError("credential_file_empty")
    return validate_webhook_url(value)


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Do not forward the credential-bearing webhook URL to another host."""

    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        return None


def _retry_after_seconds(headers: Any, body: bytes) -> float | None:
    candidate: Any = headers.get("Retry-After") if headers is not None else None
    if candidate is None:
        try:
            decoded = json.loads(body.decode("utf-8"))
            candidate = decoded.get("retry_after") if isinstance(decoded, dict) else None
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

    try:
        delay = float(candidate)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(delay) or delay < 0:
        return None
    return delay


def post_message(
    webhook_url: str,
    content: str,
    *,
    opener: Any | None = None,
    sleep_fn: Any = time.sleep,
    monotonic_fn: Any = time.monotonic,
) -> str:
    """Post one message; retry only an explicit Discord 429 rejection."""
    if not content or len(content) > 1900:
        raise AlertDeliveryError("message_content_invalid")

    target = validate_webhook_url(webhook_url)
    client = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirectHandler())
    payload = json.dumps(
        {"content": content, "allowed_mentions": {"parse": []}},
        separators=(",", ":"),
    ).encode("utf-8")
    deadline = monotonic_fn() + TOTAL_BUDGET_SECONDS

    for attempt in range(1, MAX_ATTEMPTS + 1):
        remaining = deadline - monotonic_fn()
        if remaining <= 0:
            raise AlertDeliveryError("delivery_budget_exhausted")
        request = urllib.request.Request(
            target,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "FlowlessHubBackupAlert/1.0",
            },
            method="POST",
        )

        try:
            response = client.open(request, timeout=min(HTTP_TIMEOUT_SECONDS, remaining))
        except urllib.error.HTTPError as exc:
            status = exc.code
            try:
                error_body = exc.read(8192)
            except (OSError, http.client.HTTPException):
                error_body = b""
            finally:
                try:
                    exc.close()
                except (OSError, http.client.HTTPException):
                    pass
            if status == 429 and attempt < MAX_ATTEMPTS:
                delay = _retry_after_seconds(exc.headers, error_body)
                if delay is None:
                    raise AlertDeliveryError("rate_limit_without_retry_after") from None
                if delay > MAX_RETRY_AFTER_SECONDS or delay > deadline - monotonic_fn():
                    raise AlertDeliveryError("rate_limit_retry_after_outside_budget") from None
                sleep_fn(delay)
                continue
            raise AlertDeliveryError(f"http_{status}_delivery_not_confirmed") from None
        except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException):
            # A POST may have reached Discord before the connection failed. Do not replay it.
            raise AlertDeliveryError("transport_outcome_unknown_no_retry") from None

        try:
            status = response.getcode()
            response_body = response.read(65536)
        except (OSError, TimeoutError, http.client.HTTPException):
            raise AlertDeliveryError("response_read_failed_delivery_unknown") from None
        finally:
            try:
                response.close()
            except (AttributeError, OSError, http.client.HTTPException):
                pass

        if status != 200:
            raise AlertDeliveryError(f"http_{status}_delivery_not_confirmed")
        try:
            document = json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise AlertDeliveryError("discord_response_invalid_json") from None
        message_id = document.get("id") if isinstance(document, dict) else None
        if not isinstance(message_id, str) or not message_id.isdigit():
            raise AlertDeliveryError("discord_message_id_missing")
        return message_id

    raise AlertDeliveryError("delivery_attempts_exhausted")


def _monitor_values(environment: Mapping[str, str]) -> tuple[str, str, str, str]:
    unit = environment.get("MONITOR_UNIT", "")
    result = environment.get("MONITOR_SERVICE_RESULT", "")
    exit_code = environment.get("MONITOR_EXIT_CODE", "")
    exit_status = environment.get("MONITOR_EXIT_STATUS", "")
    if not unit or not SAFE_RESULT.fullmatch(result) or not SAFE_EXIT_CODE.fullmatch(exit_code):
        raise AlertDeliveryError("systemd_monitor_context_invalid")
    if not SAFE_EXIT_STATUS.fullmatch(exit_status):
        raise AlertDeliveryError("systemd_monitor_context_invalid")
    return unit, result, exit_code, exit_status


def build_message(event: str, environment: Mapping[str, str] | None = None) -> str:
    env = environment if environment is not None else os.environ
    now_utc = datetime.now(timezone.utc)
    now_wib = now_utc.astimezone(timezone(timedelta(hours=7)))
    timestamp = f"{now_utc:%Y-%m-%d %H:%M:%S} UTC / {now_wib:%Y-%m-%d %H:%M:%S} WIB"

    if event == "test":
        return (
            "[TEST] FlowlessHub backup alert delivery\n"
            "Manual Discord delivery test. No backup service was started.\n"
            f"Time: {timestamp}"
        )

    unit, result, exit_code, exit_status = _monitor_values(env)
    if event == "success":
        if unit != "flowlesshub-backup.service" or result != "success" or exit_code != "exited" or exit_status != "0":
            raise AlertDeliveryError("backup_success_event_context_mismatch")
        return (
            "[SUCCESS] FlowlessHub scheduled backup workflow\n"
            "The backup orchestrator exited successfully. Off-site state is stage-specific; "
            "consult the backup service journal for local/off-site/retention details.\n"
            f"Result: {result} · Exit: {exit_code}/{exit_status}\n"
            f"Time: {timestamp}"
        )

    if event == "failure":
        if unit != "flowlesshub-backup.service" or result == "success":
            raise AlertDeliveryError("backup_failure_event_context_mismatch")
        return (
            "[FAILURE] FlowlessHub scheduled backup workflow\n"
            "The backup orchestrator did not complete successfully. Investigate the "
            "systemd journal; this alert does not infer which stage failed.\n"
            f"Result: {result} · Exit: {exit_code}/{exit_status}\n"
            f"Time: {timestamp}"
        )

    synthetic = {
        "test-success": ("flowlesshub-alert-test-success.service", "success", "exited", "0"),
        "test-failure": ("flowlesshub-alert-test-failure.service", "exit-code", "exited", "1"),
    }
    if event in synthetic:
        expected_unit, expected_result, expected_code, expected_status = synthetic[event]
        if unit != expected_unit or exit_code != expected_code or exit_status != expected_status:
            raise AlertDeliveryError("synthetic_event_context_mismatch")
        if expected_result is not None and result != expected_result:
            raise AlertDeliveryError("synthetic_event_context_mismatch")
        kind = "SUCCESS" if event == "test-success" else "FAILURE"
        return (
            f"[TEST — SYNTHETIC {kind}] FlowlessHub backup alert hook\n"
            "This is a disposable systemd lifecycle test, not a production backup event.\n"
            f"Source: {unit} · Result: {result} · Exit: {exit_code}/{exit_status}\n"
            f"Time: {timestamp}"
        )

    raise AlertDeliveryError("unsupported_event")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--event",
        required=True,
        choices=("success", "failure", "test", "test-success", "test-failure"),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        message = build_message(args.event)
        webhook_url = read_webhook_credential()
        message_id = post_message(webhook_url, message)
    except AlertDeliveryError as exc:
        print(
            f"ALERT_DELIVERY_RESULT=failure event={args.event} reason={exc}",
            file=sys.stderr,
            flush=True,
        )
        return 1

    print(
        f"ALERT_DELIVERY_RESULT=success event={args.event} http_status=200 message_id={message_id}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
