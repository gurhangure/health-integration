"""Launch iOS integration tests without Flutter's live-log discovery race."""

import os
import plistlib
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse


def redacted(text):
    """Decode partial output and hide VM Service authentication URLs in reports."""
    if isinstance(text, bytes):
        text = text.decode("utf-8", errors="replace")
    return re.sub(r"(?:https?|wss?)://[^\s\"'<>]+", "<VM Service URI>", text or "")


def report_output(stage, error):
    """Keep captured failure output instead of discarding TimeoutExpired details."""
    for stream in ("stdout", "stderr"):
        output = getattr(error, stream, None)
        if output:
            print(f"{stage} partial {stream}:\n{redacted(output)}", file=sys.stderr, flush=True)


def run_command(stage, args, **options):
    """Identify every command and report its actual duration, limit, and outcome."""
    command = redacted(shlex.join(args))
    started = time.monotonic()
    print(f"START {stage}: {command} (timeout={options.get('timeout')}s)", flush=True)
    try:
        result = subprocess.run(args, **options)
    except subprocess.TimeoutExpired as error:
        elapsed = time.monotonic() - started
        report_output(stage, error)
        raise RuntimeError(
            f"TIMEOUT {stage} after {elapsed:.1f}s (limit={error.timeout}s): {command}"
        ) from None
    except subprocess.CalledProcessError as error:
        elapsed = time.monotonic() - started
        report_output(stage, error)
        raise RuntimeError(
            f"FAILED {stage} after {elapsed:.1f}s (exit={error.returncode}): {command}"
        ) from None
    print(
        f"END {stage} after {time.monotonic() - started:.1f}s (exit={result.returncode})",
        flush=True,
    )
    return result


def vm_service_uri(device, pid):
    """Recover this Runner process's announcement from retained simulator logs."""
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        result = run_command(
            "VM Service URI recovery",
            [
                "xcrun", "simctl", "spawn", device, "log", "show",
                "--last", "3m", "--style", "compact",
                "--predicate", 'process == "Runner"',
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=True,
        )
        for line in result.stdout.splitlines():
            if not re.search(rf"Runner\[{pid}(?=[:\]])", line):
                continue
            match = re.search(r"The Dart VM service is listening on (http://\S+)", line)
            if match:
                uri = match.group(1)
                parsed = urlparse(uri)
                if parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
                    raise RuntimeError("Runner announced a non-loopback VM Service.")
                return uri
        time.sleep(1)
    raise RuntimeError("Runner did not announce a VM Service within 90 seconds.")


def main():
    """Install, launch paused, then relay the original suite's result unchanged."""
    device = os.environ["IOS_DEVICE_ID"]
    app = Path("build/ios/iphonesimulator/Runner.app")
    with (app / "Info.plist").open("rb") as source:
        bundle_id = plistlib.load(source)["CFBundleIdentifier"]
    run_command(
        "installation",
        ["xcrun", "simctl", "install", device, str(app)],
        check=True,
        timeout=60,
    )
    launched = run_command(
        "launch",
        [
            "xcrun", "simctl", "launch", device, bundle_id,
            "--enable-dart-profiling", "--disable-vm-service-publication",
            "--enable-checked-mode", "--verify-entry-points", "--start-paused",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    match = re.search(r": (\d+)\s*$", launched.stdout)
    if not match:
        raise RuntimeError("simctl launch did not return a Runner process ID.")
    print(f"Runner launched with PID {match.group(1)}; recovering VM Service URI.", flush=True)
    uri = vm_service_uri(device, match.group(1))
    # Do not print the URI: its path contains an ephemeral authentication code.
    print("VM Service announcement recovered; attaching integration driver.", flush=True)
    return run_command(
        "Flutter Driver attachment",
        [
            "flutter", "drive", "--no-pub", "-d", device,
            "--driver=test_driver/health_app_test.dart",
            "--target=integration_test/health_app_test.dart",
            f"--use-existing-app={uri}",
        ],
        timeout=330,
    ).returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, KeyError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f"iOS E2E launch/attach failed: {error}")
