# -*- coding: utf-8 -*-
"""Validate the fail-safe STM32H745I-DISCO CubeIDE motor integration.

This static contract catches source drift and CubeIDE metadata regressions.  It
does not replace a target build, ST-LINK download, or powered bench test.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parents[2]

CM7_MAIN = Path("firmware/algo/CM7/Core/Src/main.c")
CANONICAL_MAIN = Path(
    "algorithms/handoff/stm32_motor_control_20260823/reference/main.c"
)
CM7_GATE_C = Path("firmware/algo/CM7/Core/Src/tremor_gate.c")
CM7_GATE_H = Path("firmware/algo/CM7/Core/Inc/tremor_gate.h")
CANONICAL_GATE_C = Path("algorithms/handoff/src/gating/tremor_gate.c")
CANONICAL_GATE_H = Path("algorithms/handoff/src/gating/tremor_gate.h")
CM7_BMFLC_DIR = Path("firmware/algo/CM7/Core/Algo/bmflc")
CANONICAL_BMFLC_DIR = Path("algorithms/handoff/src/bmflc")
CM7_EHWFLC_DIR = Path("firmware/algo/CM7/Core/Algo/ehwflc")
CANONICAL_EHWFLC_DIR = Path("algorithms/handoff/src/ehwflc")
CM7_PROJECT = Path("firmware/algo/CM7/.project")
CM7_CPROJECT = Path("firmware/algo/CM7/.cproject")
CUBE_IOC = Path("firmware/algo/algo.ioc")
CM4_MAIN = Path("firmware/algo/CM4/Core/Src/main.c")

CUBE_METADATA = (
    Path("firmware/algo/.mxproject"),
    Path("firmware/algo/.project"),
    Path("firmware/algo/CM4/.cproject"),
    Path("firmware/algo/CM4/.project"),
    Path("firmware/algo/CM7/.cproject"),
    Path("firmware/algo/CM7/.project"),
)

ABSOLUTE_USER_PATH_PATTERN = re.compile(
    r"(?i)(?:\b[A-Z]:[\\/](?:Users|Documents and Settings)[\\/]"
    r"|/(?:home|Users)/[^/\s]+/)"
)

REQUIRED_RELATIVE_PATHS = (
    CM7_MAIN,
    CANONICAL_MAIN,
    CM7_GATE_C,
    CM7_GATE_H,
    CANONICAL_GATE_C,
    CANONICAL_GATE_H,
    CM7_PROJECT,
    CM7_CPROJECT,
    CUBE_IOC,
    CM4_MAIN,
)

HANDOFF_LINKS = {
    "Handoff_Control": (
        "PARENT-3-PROJECT_LOC/algorithms/handoff/src/control"
    ),
    "Handoff_Actuator": (
        "PARENT-3-PROJECT_LOC/algorithms/handoff/src/actuator"
    ),
    "Handoff_STM32_Actuator": (
        "PARENT-3-PROJECT_LOC/algorithms/handoff/"
        "stm32_motor_control_20260823/src/actuator"
    ),
}

PHYSICAL_INCLUDE_PATHS = {
    "../../../../algorithms/handoff/src/control",
    "../../../../algorithms/handoff/src/actuator",
    "../../../../algorithms/handoff/"
    "stm32_motor_control_20260823/src/actuator",
}

IOC_CONTRACT = {
    "Mcu.Name": "STM32H745XIHx",
    "Mcu.Package": "TFBGA240",
    "PG3.Signal": "GPIO_Output",
    "PA6.Signal": "GPIO_Output",
    "PK1.Signal": "GPIO_Output",
    "PA8.Signal": "S_TIM1_CH1",
    "PA8.PinAttribute": "CortexM7",
    "PE6.Signal": "GPXTI6",
    "PE6.GPIO_PuPd": "GPIO_PULLUP",
    "PE6.PinAttribute": "CortexM7",
    "PE6.ContextOwner": "CortexM7",
    "PI8.Signal": "GPXTI8",
    "PI8.GPIO_PuPd": "GPIO_PULLUP",
    "PI8.PinAttribute": "CortexM7",
    "PI8.ContextOwner": "CortexM7",
}


@dataclass(frozen=True)
class Check:
    code: str
    passed: bool
    detail: str


def _pass(code: str, detail: str) -> Check:
    return Check(code, True, detail)


def _fail(code: str, detail: str) -> Check:
    return Check(code, False, detail)


def _strip_c_comments_and_literals(source: str) -> str:
    """Blank comments and literals while keeping useful token boundaries."""

    pattern = re.compile(
        r"//[^\r\n]*|/\*.*?\*/|\"(?:\\.|[^\"\\])*\"|"
        r"'(?:\\.|[^'\\])*'",
        re.DOTALL,
    )
    return pattern.sub(lambda match: "\n" * match.group(0).count("\n"), source)


def _matching_brace(source: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def _function_body(clean_source: str, name: str) -> str | None:
    signature = re.search(
        rf"\b{re.escape(name)}\s*\([^;{{}}]*\)\s*\{{", clean_source
    )
    if signature is None:
        return None
    opening = clean_source.find("{", signature.start(), signature.end())
    closing = _matching_brace(clean_source, opening)
    if closing < 0:
        return None
    return clean_source[opening + 1 : closing]


def _read_bytes(root: Path, relative: Path) -> tuple[bytes | None, str | None]:
    path = root / relative
    try:
        return path.read_bytes(), None
    except OSError as exc:
        return None, f"{relative}: {exc}"


def _byte_identity_check(
    root: Path, code: str, target: Path, canonical: Path
) -> Check:
    target_bytes, target_error = _read_bytes(root, target)
    canonical_bytes, canonical_error = _read_bytes(root, canonical)
    errors = [error for error in (target_error, canonical_error) if error]
    if errors:
        return _fail(code, "; ".join(errors))
    if target_bytes != canonical_bytes:
        return _fail(code, f"{target} differs from {canonical}")
    return _pass(code, f"{target} is byte-identical to {canonical}")


def _directory_identity_check(
    root: Path, code: str, target: Path, canonical: Path
) -> Check:
    """Require two source directories to have the same files and bytes."""

    missing_directories = [
        str(relative)
        for relative in (target, canonical)
        if not (root / relative).is_dir()
    ]
    if missing_directories:
        return _fail(code, "missing directory: " + ", ".join(missing_directories))

    try:
        target_files = {
            path.relative_to(root / target)
            for path in (root / target).rglob("*")
            if path.is_file()
        }
        canonical_files = {
            path.relative_to(root / canonical)
            for path in (root / canonical).rglob("*")
            if path.is_file()
        }
    except OSError as exc:
        return _fail(code, f"cannot enumerate estimator mirror: {exc}")

    if target_files != canonical_files:
        missing = sorted(
            path.as_posix() for path in canonical_files - target_files
        )
        extra = sorted(path.as_posix() for path in target_files - canonical_files)
        details: list[str] = []
        if missing:
            details.append("missing: " + ", ".join(missing))
        if extra:
            details.append("unexpected: " + ", ".join(extra))
        return _fail(code, "; ".join(details))

    for relative in sorted(target_files):
        target_bytes, target_error = _read_bytes(root, target / relative)
        canonical_bytes, canonical_error = _read_bytes(
            root, canonical / relative
        )
        errors = [error for error in (target_error, canonical_error) if error]
        if errors:
            return _fail(code, "; ".join(errors))
        if target_bytes != canonical_bytes:
            return _fail(
                code,
                f"{target / relative} differs from {canonical / relative}",
            )
    return _pass(
        code,
        f"{target} mirrors all {len(target_files)} files in {canonical}",
    )


def _xml_root(root: Path, relative: Path) -> tuple[ET.Element | None, str | None]:
    try:
        return ET.parse(root / relative).getroot(), None
    except (OSError, ET.ParseError) as exc:
        return None, f"{relative}: {exc}"


def _validate_project_links(root: Path) -> Check:
    xml_root, error = _xml_root(root, CM7_PROJECT)
    if xml_root is None:
        return _fail("cm7-project-links", error or "unreadable .project")

    links: dict[str, str] = {}
    duplicate_names: set[str] = set()
    for link in xml_root.findall("./linkedResources/link"):
        name = link.findtext("name")
        uri = link.findtext("locationURI")
        if name is None or not name.startswith("Handoff_"):
            continue
        if name in links:
            duplicate_names.add(name)
        links[name] = uri or ""

    if duplicate_names or links != HANDOFF_LINKS:
        problems: list[str] = []
        if duplicate_names:
            problems.append("duplicate links: " + ", ".join(sorted(duplicate_names)))
        missing = sorted(set(HANDOFF_LINKS) - set(links))
        extra = sorted(set(links) - set(HANDOFF_LINKS))
        wrong = sorted(
            name
            for name in set(links) & set(HANDOFF_LINKS)
            if links[name] != HANDOFF_LINKS[name]
        )
        if missing:
            problems.append("missing: " + ", ".join(missing))
        if extra:
            problems.append("unexpected: " + ", ".join(extra))
        if wrong:
            problems.append("wrong URI: " + ", ".join(wrong))
        return _fail("cm7-project-links", "; ".join(problems))
    return _pass("cm7-project-links", "three repo-relative Handoff links are exact")


def _validate_metadata_portability(root: Path) -> Check:
    problems: list[str] = []
    for relative in CUBE_METADATA:
        try:
            text = (root / relative).read_text(encoding="utf-8")
        except OSError as exc:
            problems.append(f"{relative}: {exc}")
            continue
        match = ABSOLUTE_USER_PATH_PATTERN.search(text)
        if match is not None:
            problems.append(f"{relative}: absolute user path {match.group(0)!r}")
    if problems:
        return _fail("cubeide-metadata-portable", "; ".join(problems))
    return _pass(
        "cubeide-metadata-portable",
        "CubeIDE metadata contains no absolute user-home paths",
    )


def _configuration_name(configuration: ET.Element) -> str | None:
    for storage in configuration.findall("./storageModule"):
        name = storage.get("name")
        if name in {"Debug", "Release"}:
            return name
    return None


def _validate_cproject(root: Path) -> list[Check]:
    relative = CM7_CPROJECT
    path = root / relative
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        detail = f"{relative}: {exc}"
        return [
            _fail("cm7-cproject-no-user-path", detail),
            _fail("cm7-cproject-debug", detail),
            _fail("cm7-cproject-release", detail),
        ]

    user_path_pattern = re.compile(r"C:[\\/]Users[\\/]banny[\\/]", re.IGNORECASE)
    no_user_path = (
        _fail(
            "cm7-cproject-no-user-path",
            "contains forbidden C:\\Users\\banny absolute path",
        )
        if user_path_pattern.search(raw)
        else _pass("cm7-cproject-no-user-path", "no banny absolute user path")
    )

    try:
        xml_root = ET.fromstring(raw)
    except ET.ParseError as exc:
        detail = f"{relative}: {exc}"
        return [
            no_user_path,
            _fail("cm7-cproject-debug", detail),
            _fail("cm7-cproject-release", detail),
        ]

    configurations: dict[str, ET.Element] = {}
    duplicates: set[str] = set()
    for configuration in xml_root.findall("./storageModule/cconfiguration"):
        name = _configuration_name(configuration)
        if name is None:
            continue
        if name in configurations:
            duplicates.add(name)
        configurations[name] = configuration

    checks = [no_user_path]
    expected_sources = set(HANDOFF_LINKS)
    for name in ("Debug", "Release"):
        code = f"cm7-cproject-{name.lower()}"
        configuration = configurations.get(name)
        if configuration is None:
            checks.append(_fail(code, f"missing {name} configuration"))
            continue
        if name in duplicates:
            checks.append(_fail(code, f"duplicate {name} configurations"))
            continue

        source_names = [
            entry.get("name", "")
            for entry in configuration.findall(".//sourceEntries/entry")
        ]
        source_counts = {
            expected: source_names.count(expected) for expected in expected_sources
        }
        include_values = {
            value
            for node in configuration.findall(".//listOptionValue")
            if (value := node.get("value")) is not None
        }
        missing_includes = sorted(PHYSICAL_INCLUDE_PATHS - include_values)
        invalid_source_counts = sorted(
            source for source, count in source_counts.items() if count != 1
        )
        if invalid_source_counts or missing_includes:
            details: list[str] = []
            if invalid_source_counts:
                details.append(
                    "sourceEntry count is not one: "
                    + ", ".join(invalid_source_counts)
                )
            if missing_includes:
                details.append("missing includes: " + ", ".join(missing_includes))
            checks.append(_fail(code, "; ".join(details)))
        else:
            checks.append(
                _pass(
                    code,
                    "three Handoff sourceEntry and physical include paths are exact",
                )
            )
    return checks


def _parse_ioc(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key] = value
    return result


def _validate_ioc(root: Path) -> Check:
    path = root / CUBE_IOC
    try:
        values = _parse_ioc(path.read_text(encoding="utf-8"))
    except OSError as exc:
        return _fail("disco-ioc-mapping", f"{CUBE_IOC}: {exc}")

    mismatches = [
        f"{key}={values.get(key)!r} (expected {expected!r})"
        for key, expected in IOC_CONTRACT.items()
        if values.get(key) != expected
    ]
    if mismatches:
        return _fail("disco-ioc-mapping", "; ".join(mismatches))
    return _pass(
        "disco-ioc-mapping",
        "STM32H745XIHx/TFBGA240 motor and encoder pins match the DISCO contract",
    )


def _validate_cm4(root: Path) -> list[Check]:
    path = root / CM4_MAIN
    try:
        clean = _strip_c_comments_and_literals(path.read_text(encoding="utf-8"))
    except OSError as exc:
        detail = f"{CM4_MAIN}: {exc}"
        return [
            _fail("cm4-hsem-stop-handshake", detail),
            _fail("cm4-idle-main", detail),
            _fail("cm4-no-conflicting-init", detail),
            _fail("cm4-error-fail-stop", detail),
        ]

    main_body = _function_body(clean, "main")
    if main_body is None:
        detail = "main() definition not found"
        return [
            _fail("cm4-hsem-stop-handshake", detail),
            _fail("cm4-idle-main", detail),
            _fail("cm4-no-conflicting-init", detail),
            _fail("cm4-error-fail-stop", "Error_Handler not evaluated without main"),
        ]

    ordered_tokens = (
        "__HAL_RCC_HSEM_CLK_ENABLE",
        "HAL_HSEM_ActivateNotification",
        "HAL_PWREx_ClearPendingEvent",
        "HAL_PWREx_EnterSTOPMode",
        "__HAL_HSEM_CLEAR_FLAG",
        "HAL_Init",
    )
    positions = [main_body.find(token) for token in ordered_tokens]
    handshake_ok = (
        all(position >= 0 for position in positions)
        and positions == sorted(positions)
        and "HSEM_ID_0" in main_body
        and "PWR_D2_DOMAIN" in main_body
    )
    handshake = (
        _pass(
            "cm4-hsem-stop-handshake",
            "HSEM notification, D2 STOP, wake acknowledgement, then HAL_Init",
        )
        if handshake_ok
        else _fail(
            "cm4-hsem-stop-handshake",
            "missing or misordered HSEM/D2 STOP boot handshake",
        )
    )

    idle_matches = list(re.finditer(r"\bwhile\s*\(\s*1\s*\)\s*\{", main_body))
    idle_ok = False
    if len(idle_matches) == 1:
        opening = main_body.find("{", idle_matches[0].start(), idle_matches[0].end())
        closing = _matching_brace(main_body, opening)
        idle_ok = closing >= 0 and not main_body[opening + 1 : closing].strip()
    idle = (
        _pass("cm4-idle-main", "main ends in one empty infinite idle loop")
        if idle_ok
        else _fail("cm4-idle-main", "main must contain one empty while (1) loop")
    )

    forbidden_call_pattern = re.compile(
        r"\b(MX_(?:GPIO|ETH|FMC|LTDC|SAI\w*|SDMMC\w*|USB\w*)_Init)\s*\("
    )
    forbidden_calls = sorted(set(forbidden_call_pattern.findall(main_body)))
    no_conflicting_init = (
        _fail(
            "cm4-no-conflicting-init",
            "main calls CM7-conflicting init: " + ", ".join(forbidden_calls),
        )
        if forbidden_calls
        else _pass(
            "cm4-no-conflicting-init",
            "main does not call GPIO/ETH/FMC/LTDC/SAI/SDMMC/USB init",
        )
    )

    error_body = _function_body(clean, "Error_Handler")
    error_loop_ok = False
    if error_body is not None:
        error_loop = re.search(r"\bwhile\s*\(\s*1\s*\)\s*\{", error_body)
        if error_loop is not None:
            opening = error_body.find("{", error_loop.start(), error_loop.end())
            closing = _matching_brace(error_body, opening)
            error_loop_ok = closing >= 0
    fail_stop_ok = (
        error_body is not None
        and "__disable_irq" in error_body
        and error_loop_ok
    )
    fail_stop = (
        _pass("cm4-error-fail-stop", "Error_Handler disables IRQ and loops forever")
        if fail_stop_ok
        else _fail(
            "cm4-error-fail-stop",
            "Error_Handler must disable IRQ and loop forever",
        )
    )
    return [handshake, idle, no_conflicting_init, fail_stop]


def _zero_literal(value: str) -> bool:
    compact = re.sub(r"[\s()]", "", value)
    return compact in {"0", "0U", "0u", "0UL", "0ul", "0LU", "0lu"}


def validate_cm7_safety_source(source: str) -> Check:
    """Validate the compile-time and runtime motor locks in CM7 source."""

    clean = _strip_c_comments_and_literals(source)
    definitions = re.findall(
        r"(?m)^\s*#\s*define\s+MOTOR_BENCH_CONFIG_APPROVED\s+([^\r\n]+)",
        clean,
    )
    bench_lock_ok = len(definitions) == 1 and _zero_literal(definitions[0])
    max_ccr_definitions = re.findall(
        r"(?m)^\s*#\s*define\s+MOTOR_MAX_ACTIVE_CCR\s+([^\r\n]+)",
        clean,
    )
    max_ccr_lock_ok = (
        len(max_ccr_definitions) == 1
        and _zero_literal(max_ccr_definitions[0])
    )
    max_ccr_binding_ok = re.search(
        r"\bhal_config\s*\.\s*max_active_ccr\s*=\s*"
        r"MOTOR_MAX_ACTIVE_CCR\s*;",
        clean,
    ) is not None
    armed_one = re.search(
        r"\bmotor_runtime_armed\s*=(?!=)\s*\(?\s*1(?:[uUlL]*)\s*\)?\s*;",
        clean,
    )
    if (
        not bench_lock_ok
        or not max_ccr_lock_ok
        or not max_ccr_binding_ok
        or armed_one is not None
    ):
        details: list[str] = []
        if not bench_lock_ok:
            details.append("MOTOR_BENCH_CONFIG_APPROVED must be defined once as zero")
        if not max_ccr_lock_ok:
            details.append("MOTOR_MAX_ACTIVE_CCR must be defined once as zero")
        if not max_ccr_binding_ok:
            details.append("HAL max_active_ccr must be bound to MOTOR_MAX_ACTIVE_CCR")
        if armed_one is not None:
            details.append("motor_runtime_armed must never be assigned one")
        return _fail("cm7-motor-safety-lock", "; ".join(details))
    return _pass(
        "cm7-motor-safety-lock",
        "bench approval and HAL integer CCR cap are zero; runtime arm has no assignment to one",
    )


def _validate_cm7_safety_lock(root: Path) -> Check:
    path = root / CM7_MAIN
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        return _fail("cm7-motor-safety-lock", f"{CM7_MAIN}: {exc}")
    return validate_cm7_safety_source(source)


def validate_repository(repo_root: Path = REPO_ROOT) -> list[Check]:
    root = Path(repo_root).resolve()
    checks = [
        _byte_identity_check(
            root, "cm7-main-byte-identical", CM7_MAIN, CANONICAL_MAIN
        ),
        _byte_identity_check(
            root, "cm7-gate-c-byte-identical", CM7_GATE_C, CANONICAL_GATE_C
        ),
        _byte_identity_check(
            root, "cm7-gate-h-byte-identical", CM7_GATE_H, CANONICAL_GATE_H
        ),
        _directory_identity_check(
            root,
            "cm7-bmflc-directory-byte-identical",
            CM7_BMFLC_DIR,
            CANONICAL_BMFLC_DIR,
        ),
        _directory_identity_check(
            root,
            "cm7-ehwflc-directory-byte-identical",
            CM7_EHWFLC_DIR,
            CANONICAL_EHWFLC_DIR,
        ),
        _validate_project_links(root),
        _validate_metadata_portability(root),
    ]
    checks.extend(_validate_cproject(root))
    checks.append(_validate_ioc(root))
    checks.extend(_validate_cm4(root))
    checks.append(_validate_cm7_safety_lock(root))
    return checks


def _print_report(checks: list[Check]) -> None:
    for check in checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"[{status}] {check.code}: {check.detail}")
    failures = sum(not check.passed for check in checks)
    print(f"Summary: {len(checks) - failures} passed, {failures} failed")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=REPO_ROOT,
        help="repository root (defaults to the root containing this script)",
    )
    args = parser.parse_args(argv)
    checks = validate_repository(args.repo_root)
    _print_report(checks)
    return 0 if all(check.passed for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
