# -*- coding: utf-8 -*-
"""Static integration contract for the canonical STM32 motor ``main.c``.

This is intentionally stricter than a compiler.  It protects safety and
telemetry ownership rules that can still compile when wired incorrectly.
It is not a substitute for a CubeIDE target build or a powered bench test.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
MOTOR_HANDOFF = (
    REPO_ROOT / "algorithms" / "handoff" / "stm32_motor_control_20260823"
)
DEFAULT_MANIFEST = MOTOR_HANDOFF / "authoritative_modules.json"
DEFAULT_MAIN = MOTOR_HANDOFF / "reference" / "main.c"
DEFAULT_SHADOW_MAIN = (
    REPO_ROOT
    / "algorithms"
    / "handoff"
    / "stm32_gate_upgrade_20260822"
    / "reference"
    / "main.c"
)

EXPECTED_MODULE_NAMES = {
    "bmflc",
    "ehwflc_kf",
    "tremor_gate",
    "suppression_control",
    "motor_command_mapper",
    "quadrature_encoder",
    "motor_position_guard",
    "tb6612_driver",
    "stm32_tb6612_hal",
}

EXPECTED_PRIMARY_HEADERS = {
    "suppression_control.h",
    "motor_command_mapper.h",
    "quadrature_encoder.h",
    "motor_position_guard.h",
    "tb6612_driver.h",
    "stm32_tb6612_hal.h",
}

EXPECTED_CANONICAL_MAIN = (
    "algorithms/handoff/stm32_motor_control_20260823/reference/main.c"
)

EXPECTED_SHADOW_REFERENCE = (
    "algorithms/handoff/stm32_gate_upgrade_20260822/reference/main.c"
)
EXPECTED_SHADOW_GIT_BLOB_SHA1 = "468f28802b57b5bd9f1fa7d4d51def4007bc2b7d"

EXPECTED_MODULE_CONTRACT = {
    "bmflc": {
        "header": "algorithms/handoff/src/bmflc/BMFLC_step.h",
        "source": "algorithms/handoff/src/bmflc/BMFLC_step.c",
        "required_symbols": {"BMFLC_step"},
    },
    "ehwflc_kf": {
        "header": "algorithms/handoff/src/ehwflc/eHWFLC_KF_step.h",
        "source": "algorithms/handoff/src/ehwflc/eHWFLC_KF_step.c",
        "required_symbols": {"eHWFLC_KF_step"},
    },
    "tremor_gate": {
        "header": "algorithms/handoff/src/gating/tremor_gate.h",
        "source": "algorithms/handoff/src/gating/tremor_gate.c",
        "required_symbols": {
            "TremorGate_Init",
            "TremorGate_IsReady",
            "TremorGate_Update",
        },
    },
    "suppression_control": {
        "header": "algorithms/handoff/src/control/suppression_control.h",
        "source": "algorithms/handoff/src/control/suppression_control.c",
        "required_symbols": {
            "SuppressionControl_Init",
            "SuppressionControl_Update",
            "SuppressionControl_Release",
        },
    },
    "motor_command_mapper": {
        "header": "algorithms/handoff/src/control/motor_command_mapper.h",
        "source": "algorithms/handoff/src/control/motor_command_mapper.c",
        "required_symbols": {
            "MotorCommandMapper_Init",
            "MotorCommandMapper_Update",
        },
    },
    "quadrature_encoder": {
        "header": "algorithms/handoff/src/actuator/quadrature_encoder.h",
        "source": "algorithms/handoff/src/actuator/quadrature_encoder.c",
        "required_symbols": {
            "QuadratureEncoder_Init",
            "QuadratureEncoder_OnEdge",
            "QuadratureEncoder_Snapshot",
        },
    },
    "motor_position_guard": {
        "header": "algorithms/handoff/src/actuator/motor_position_guard.h",
        "source": "algorithms/handoff/src/actuator/motor_position_guard.c",
        "required_symbols": {
            "MotorPositionGuard_Init",
            "MotorPositionGuard_SetZero",
            "MotorPositionGuard_Update",
        },
    },
    "tb6612_driver": {
        "header": "algorithms/handoff/src/actuator/tb6612_driver.h",
        "source": "algorithms/handoff/src/actuator/tb6612_driver.c",
        "required_symbols": {"TB6612Driver_Init", "TB6612Driver_Update"},
    },
    "stm32_tb6612_hal": {
        "header": (
            "algorithms/handoff/stm32_motor_control_20260823/"
            "src/actuator/stm32_tb6612_hal.h"
        ),
        "source": (
            "algorithms/handoff/stm32_motor_control_20260823/"
            "src/actuator/stm32_tb6612_hal.c"
        ),
        "required_symbols": {
            "STM32_TB6612_HAL_Init",
            "STM32_TB6612_HAL_Apply",
            "STM32_TB6612_HAL_ForceSafe",
        },
    },
}

# These belong behind SuppressionControl and must not reappear in main.c.
FORBIDDEN_DIRECT_ESTIMATOR_TOKENS = {
    "BMFLC_step",
    "eHWFLC_KF_step",
    "freqEstimate",
    "tremor_active",
    "TREMOR_FREQ_ON_MIN_HZ",
    "TREMOR_FREQ_ON_MAX_HZ",
    "TREMOR_FREQ_OFF_MIN_HZ",
    "TREMOR_FREQ_OFF_MAX_HZ",
}

FORBIDDEN_LEGACY_MAIN_TOKENS = {
    "FakeApp_Process",
    "Read_IMU_TestData",
    "Bandpass_TremorGate_Update",
    "Tremor_Detector_Update",
    "Motor_Control",
    "Motor_UpdateWithDeadtime",
    "Actuator_StateMachine_Reset",
    "Actuator_StateMachine_Update",
}

PIPELINE_APIS = {
    "SuppressionControl_Update",
    "MotorCommandMapper_Update",
    "TB6612Driver_Update",
    "MotorPositionGuard_Update",
    "STM32_TB6612_HAL_Apply",
}


@dataclass(frozen=True)
class ValidationIssue:
    code: str
    message: str


@dataclass(frozen=True)
class CFunction:
    name: str
    body: str
    start: int
    body_start: int
    end: int


@dataclass(frozen=True)
class CIfBlock:
    condition: str
    body: str
    start: int
    body_start: int
    end: int
    else_body: str | None


def _blank_preserving_newlines(match: re.Match[str]) -> str:
    value = match.group(0)
    return "".join("\n" if character == "\n" else " " for character in value)


def strip_c_comments_and_literals(source: str) -> str:
    """Blank comments/string literals while preserving offsets and newlines."""

    pattern = re.compile(
        r"//[^\r\n]*|/\*.*?\*/|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'",
        re.DOTALL,
    )
    return pattern.sub(_blank_preserving_newlines, source)


def _matching_delimiter(source: str, opening: int, left: str, right: str) -> int:
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == left:
            depth += 1
        elif character == right:
            depth -= 1
            if depth == 0:
                return index
    return -1


def extract_functions(clean_source: str) -> dict[str, CFunction]:
    """Extract ordinary C function definitions from already-cleaned source."""

    signature = re.compile(
        r"(?m)^\s*(?!if\b|for\b|while\b|switch\b)"
        r"(?:static\s+)?(?:inline\s+)?"
        r"(?:[A-Za-z_]\w*\s+|[A-Za-z_]\w*\s*\*\s*)+"
        r"(?P<name>[A-Za-z_]\w*)\s*"
        r"\([^;{}]*\)\s*\{"
    )
    functions: dict[str, CFunction] = {}
    for match in signature.finditer(clean_source):
        opening = clean_source.find("{", match.start(), match.end())
        closing = _matching_delimiter(clean_source, opening, "{", "}")
        if closing < 0:
            continue
        name = match.group("name")
        functions[name] = CFunction(
            name=name,
            body=clean_source[opening + 1 : closing],
            start=match.start(),
            body_start=opening + 1,
            end=closing + 1,
        )
    return functions


def extract_if_blocks(clean_source: str) -> list[CIfBlock]:
    blocks: list[CIfBlock] = []
    for match in re.finditer(r"\bif\s*\(", clean_source):
        condition_open = clean_source.find("(", match.start(), match.end())
        condition_close = _matching_delimiter(
            clean_source, condition_open, "(", ")"
        )
        if condition_close < 0:
            continue
        cursor = condition_close + 1
        while cursor < len(clean_source) and clean_source[cursor].isspace():
            cursor += 1
        if cursor >= len(clean_source) or clean_source[cursor] != "{":
            continue
        body_close = _matching_delimiter(clean_source, cursor, "{", "}")
        if body_close < 0:
            continue
        after = body_close + 1
        while after < len(clean_source) and clean_source[after].isspace():
            after += 1
        else_body: str | None = None
        if clean_source.startswith("else", after):
            else_open = after + len("else")
            while (
                else_open < len(clean_source)
                and clean_source[else_open].isspace()
            ):
                else_open += 1
            if else_open < len(clean_source) and clean_source[else_open] == "{":
                else_close = _matching_delimiter(
                    clean_source, else_open, "{", "}"
                )
                if else_close >= 0:
                    else_body = clean_source[else_open + 1 : else_close]
        blocks.append(
            CIfBlock(
                condition=clean_source[condition_open + 1 : condition_close],
                body=clean_source[cursor + 1 : body_close],
                start=match.start(),
                body_start=cursor + 1,
                end=body_close + 1,
                else_body=else_body,
            )
        )
    return blocks


def _local_includes(source: str) -> list[str]:
    return re.findall(r'^\s*#\s*include\s*"([^"\r\n]+)"', source, re.MULTILINE)


def _has_token(source: str, token: str) -> bool:
    return re.search(rf"\b{re.escape(token)}\b", source) is not None


def _assignment_rhs(clean_source: str, lhs_pattern: str) -> list[str]:
    return [
        match.group("rhs").strip()
        for match in re.finditer(
            rf"{lhs_pattern}\s*=(?!=)\s*(?P<rhs>[^;]+);", clean_source
        )
    ]


def _reachable_function_text(
    start_name: str, functions: dict[str, CFunction]
) -> str:
    """Return local function bodies reachable from ``start_name``."""

    pending = [start_name]
    visited: set[str] = set()
    bodies: list[str] = []
    while pending:
        name = pending.pop()
        if name in visited or name not in functions:
            continue
        visited.add(name)
        body = functions[name].body
        bodies.append(body)
        for candidate in functions:
            if candidate not in visited and _has_token(body, candidate):
                pending.append(candidate)
    return "\n".join(bodies)


def _validate_scheduler_overrun(
    main_body: str,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    pending_rhs = _assignment_rhs(main_body, r"\bpending_ticks")
    if len(pending_rhs) != 1 or not (
        _has_token(pending_rhs[0], "software_tick_count")
        and _has_token(pending_rhs[0], "control_tick_count")
        and "-" in pending_rhs[0]
    ):
        issues.append(
            ValidationIssue(
                "scheduler-pending-count",
                "scheduler must derive pending_ticks from software minus consumed ticks",
            )
        )

    overrun_rhs = _assignment_rhs(
        main_body, r"\bscheduler_overrun_this_tick"
    )
    if len(overrun_rhs) != 1 or not _has_token(overrun_rhs[0], "pending_ticks"):
        issues.append(
            ValidationIssue(
                "scheduler-overrun-detection",
                "scheduler_overrun_this_tick must be derived from pending_ticks",
            )
        )

    overrun_blocks = [
        block
        for block in extract_if_blocks(main_body)
        if _has_token(block.condition, "scheduler_overrun_this_tick")
    ]
    if len(overrun_blocks) != 1:
        issues.append(
            ValidationIssue(
                "scheduler-overrun-guard",
                "main must have exactly one scheduler-overrun control guard",
            )
        )
        return issues

    overrun_body = overrun_blocks[0].body
    if not (
        _has_token(overrun_body, "ControlPipeline_RejectStaleSample")
        or _has_token(overrun_body, "ControlPipeline_ForceSafe")
    ):
        issues.append(
            ValidationIssue(
                "scheduler-overrun-failsafe",
                "scheduler overrun path must reject the sample or force safe",
            )
        )
    if _has_token(overrun_body, "ControlPipeline_100HzFreshSample"):
        issues.append(
            ValidationIssue(
                "scheduler-overrun-fresh-call",
                "scheduler overrun path must not run the fresh-sample pipeline",
            )
        )
    fresh_call_count = len(
        re.findall(r"\bControlPipeline_100HzFreshSample\s*\(", main_body)
    )
    if (
        overrun_blocks[0].else_body is None
        or not _has_token(
            overrun_blocks[0].else_body, "ControlPipeline_100HzFreshSample"
        )
        or fresh_call_count != 1
    ):
        issues.append(
            ValidationIssue(
                "scheduler-overrun-isolation",
                "the sole fresh pipeline call must be isolated in the "
                "non-overrun else branch",
            )
        )
    return issues


def _validate_active_apply_critical_section(
    functions: dict[str, CFunction],
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    pipeline = functions.get("ControlPipeline_100HzFreshSample")
    if pipeline is None:
        return issues

    candidate_apply_pattern = re.compile(
        r"STM32_TB6612_HAL_Apply\s*\(\s*[^,]+,\s*&\s*candidate\s*\)"
    )
    active_blocks = [
        block
        for block in extract_if_blocks(pipeline.body)
        if _has_token(block.condition, "candidate_active")
        and _has_token(block.condition, "position_allowed")
        and candidate_apply_pattern.search(block.body) is not None
    ]
    if len(active_blocks) != 1:
        return [
            ValidationIssue(
                "active-apply-guard",
                "exactly one ACTIVE candidate Apply branch must be identifiable",
            )
        ]

    active_body = active_blocks[0].body
    save_match = re.search(
        r"\b(?P<var>[A-Za-z_]\w*)\s*=\s*__get_PRIMASK\s*\(\s*\)\s*;",
        active_body,
    )
    disable_match = re.search(r"\b__disable_irq\s*\(\s*\)\s*;", active_body)
    apply_matches = list(candidate_apply_pattern.finditer(active_body))
    restore_match = None
    if save_match is not None:
        restore_match = re.search(
            rf"\b__set_PRIMASK\s*\(\s*{re.escape(save_match.group('var'))}"
            r"\s*\)\s*;",
            active_body,
        )

    final_rhs = _assignment_rhs(active_body, r"\bfinal_recheck_ok")
    final_assignment = re.search(r"\bfinal_recheck_ok\s*=", active_body)
    guarded_apply_blocks = [
        block
        for block in extract_if_blocks(active_body)
        if _has_token(block.condition, "final_recheck_ok")
        and candidate_apply_pattern.search(block.body) is not None
    ]

    structure_ok = (
        save_match is not None
        and disable_match is not None
        and len(apply_matches) == 1
        and restore_match is not None
        and final_assignment is not None
        and len(guarded_apply_blocks) == 1
        and save_match.start()
        < disable_match.start()
        < final_assignment.start()
        < apply_matches[0].start()
        < restore_match.start()
        and "return" not in active_body[
            disable_match.end() : restore_match.start()
        ]
        and not _has_token(active_body, "__enable_irq")
        and not _has_token(
            guarded_apply_blocks[0].body, "__set_PRIMASK"
        )
    )
    if not structure_ok:
        issues.append(
            ValidationIssue(
                "active-critical-section",
                "ACTIVE Apply must save PRIMASK, disable IRQ, recheck, Apply, "
                "then restore the saved PRIMASK without an early return",
            )
        )

    required_rechecks = {
        "fresh_sample_available",
        "scheduler_overrun_this_tick",
        "tick_flag",
        "software_tick_count",
        "control_tick_count",
        "motor_runtime_fault_latched",
        "motor_runtime_armed",
        "motor_bench_config_approved",
        "quadrature_encoder.initialized",
        "quadrature_encoder.invalid_transition_latched",
        "quadrature_encoder.overflow_latched",
        "motor_position_guard.zeroed",
        "motor_position_guard.fault_latched",
    }
    if len(final_rhs) != 1:
        missing_rechecks = sorted(required_rechecks)
    else:
        missing_rechecks = sorted(
            token for token in required_rechecks if token not in final_rhs[0]
        )
    if missing_rechecks:
        issues.append(
            ValidationIssue(
                "active-final-recheck",
                "ACTIVE commit recheck is missing: " + ", ".join(missing_rechecks),
            )
        )
    return issues


def load_manifest(path: Path = DEFAULT_MANIFEST) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def validate_manifest(
    manifest_path: Path = DEFAULT_MANIFEST,
    repo_root: Path = REPO_ROOT,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    try:
        manifest = load_manifest(manifest_path)
    except (OSError, json.JSONDecodeError) as exc:
        return [ValidationIssue("manifest-unreadable", str(exc))]

    if manifest.get("schema_version") != 1:
        issues.append(
            ValidationIssue("manifest-schema", "schema_version must be 1")
        )

    if manifest.get("canonical_main") != EXPECTED_CANONICAL_MAIN:
        issues.append(
            ValidationIssue(
                "manifest-canonical-main",
                f"canonical_main must be {EXPECTED_CANONICAL_MAIN}",
            )
        )

    sealed_shadow = manifest.get("sealed_shadow_reference")
    if not isinstance(sealed_shadow, dict) or (
        sealed_shadow.get("path") != EXPECTED_SHADOW_REFERENCE
        or sealed_shadow.get("git_blob_sha1")
        != EXPECTED_SHADOW_GIT_BLOB_SHA1
    ):
        issues.append(
            ValidationIssue(
                "manifest-shadow-seal",
                "sealed 0822 path/blob hash differs from the reviewed reference",
            )
        )

    primary_headers = set(manifest.get("main_primary_headers", []))
    if primary_headers != EXPECTED_PRIMARY_HEADERS:
        issues.append(
            ValidationIssue(
                "manifest-primary-headers",
                "main_primary_headers must equal the reviewed six-header set",
            )
        )

    modules = manifest.get("modules", [])
    names = [module.get("name") for module in modules]
    if set(names) != EXPECTED_MODULE_NAMES or len(names) != len(
        EXPECTED_MODULE_NAMES
    ):
        issues.append(
            ValidationIssue(
                "manifest-module-set",
                "module names must equal the reviewed nine-module set exactly",
            )
        )

    all_paths: list[str] = []
    for module in modules:
        name = str(module.get("name", "<unnamed>"))
        header = module.get("header")
        source = module.get("source")
        symbols = module.get("required_symbols")
        if not isinstance(header, str) or not isinstance(source, str):
            issues.append(
                ValidationIssue(
                    "manifest-module-path", f"{name}: header/source path missing"
                )
            )
            continue
        expected = EXPECTED_MODULE_CONTRACT.get(name)
        if expected is not None and (
            header != expected["header"] or source != expected["source"]
        ):
            issues.append(
                ValidationIssue(
                    "manifest-authoritative-path",
                    f"{name}: must use the reviewed handoff header/source paths",
                )
            )
        all_paths.extend([header, source])
        if not isinstance(symbols, list) or not symbols:
            issues.append(
                ValidationIssue(
                    "manifest-module-symbols", f"{name}: required_symbols missing"
                )
            )
            continue
        if expected is not None and set(symbols) != expected["required_symbols"]:
            issues.append(
                ValidationIssue(
                    "manifest-api-contract",
                    f"{name}: required_symbols differs from reviewed API contract",
                )
            )
        header_path = repo_root / header
        source_path = repo_root / source
        for role, path in (("header", header_path), ("source", source_path)):
            if not path.is_file():
                issues.append(
                    ValidationIssue(
                        "module-file-missing", f"{name}: {role} missing: {path}"
                    )
                )
        if header_path.is_file():
            header_text = header_path.read_text(encoding="utf-8")
            for symbol in symbols:
                if not _has_token(header_text, str(symbol)):
                    issues.append(
                        ValidationIssue(
                            "module-api-missing",
                            f"{name}: {symbol} not declared by {header}",
                        )
                    )

    if len(all_paths) != len(set(all_paths)):
        issues.append(
            ValidationIssue(
                "manifest-duplicate-path", "module header/source paths must be unique"
            )
        )
    return issues


def validate_motor_main_source(source: str) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    clean = strip_c_comments_and_literals(source)

    absolute_include = re.search(
        r'^\s*#\s*include\s*[<"](?:[A-Za-z]:[/\\]|[/\\](?:Users|home)[/\\])',
        source,
        re.IGNORECASE | re.MULTILINE,
    )
    if absolute_include is not None:
        issues.append(
            ValidationIssue(
                "absolute-include", "main.c contains a machine-specific include path"
            )
        )

    includes = [Path(value.replace("\\", "/")).name for value in _local_includes(source)]
    for header in sorted(EXPECTED_PRIMARY_HEADERS):
        count = includes.count(header)
        if count != 1:
            issues.append(
                ValidationIssue(
                    "primary-header-count",
                    f"{header} must be included exactly once (found {count})",
                )
            )
    forbidden_direct_headers = {
        "tremor_gate.h",
        "BMFLC_step.h",
        "eHWFLC_KF_step.h",
    }
    direct_forbidden = sorted(forbidden_direct_headers.intersection(includes))
    if direct_forbidden:
        issues.append(
            ValidationIssue(
                "authority-bypass-header",
                "main.c must not directly include " + ", ".join(direct_forbidden),
            )
        )

    for token in sorted(FORBIDDEN_DIRECT_ESTIMATOR_TOKENS):
        if _has_token(clean, token):
            issues.append(
                ValidationIssue(
                    "legacy-estimator-authority",
                    f"main.c must not reference {token}; use SuppressionControl",
                )
            )

    for token in sorted(FORBIDDEN_LEGACY_MAIN_TOKENS):
        if _has_token(clean, token):
            issues.append(
                ValidationIssue(
                    "legacy-main-path",
                    f"canonical main.c must not retain legacy path {token}",
                )
            )

    if _has_token(clean, "COMM_TEST_GATE_AS_MOTOR_STATUS"):
        issues.append(
            ValidationIssue(
                "gate-as-motor-mode",
                "gate-as-motor UART compatibility mode is forbidden",
            )
        )

    motor_enabled_rhs = _assignment_rhs(
        clean, r"\b[A-Za-z_]\w*\.motor_enabled"
    )
    if motor_enabled_rhs != ["motor_output_active_debug"]:
        issues.append(
            ValidationIssue(
                "uart-motor-semantics",
                "UART motor_enabled must be assigned exactly once and directly "
                "from motor_output_active_debug",
            )
        )

    functions = extract_functions(clean)
    main_function = functions.get("main")
    if main_function is None:
        issues.append(ValidationIssue("main-missing", "main() definition not found"))
        return issues

    issues.extend(_validate_scheduler_overrun(main_function.body))
    issues.extend(_validate_active_apply_critical_section(functions))

    for api in sorted(PIPELINE_APIS):
        owners = [
            function.name
            for function in functions.values()
            if _has_token(function.body, api)
        ]
        if not owners:
            issues.append(
                ValidationIssue(
                    "pipeline-api-missing", f"canonical pipeline does not call {api}"
                )
            )

    generation_increments = re.findall(
        r"(?:\bimu_sample_generation\s*\+\+|\+\+\s*imu_sample_generation\b)",
        clean,
    )
    if len(generation_increments) != 1:
        issues.append(
            ValidationIssue(
                "sample-generation-increment",
                "imu_sample_generation must be incremented exactly once in source",
            )
        )

    main_if_blocks = extract_if_blocks(main_function.body)
    success_blocks = [
        block
        for block in main_if_blocks
        if _has_token(block.condition, "HAL_OK")
        and _has_token(block.body, "imu_sample_generation")
        and "++" in block.body
    ]
    if len(success_blocks) != 1:
        issues.append(
            ValidationIssue(
                "sample-generation-success-guard",
                "generation increment must occur in exactly one HAL_OK success block",
            )
        )

    fresh_rhs = _assignment_rhs(clean, r"\bfresh_sample_available")
    valid_fresh_rhs = [
        rhs
        for rhs in fresh_rhs
        if _has_token(rhs, "imu_sample_generation")
        and _has_token(rhs, "last_controlled_sample_generation")
        and "!=" in rhs
    ]
    if len(valid_fresh_rhs) != 1:
        issues.append(
            ValidationIssue(
                "fresh-generation-comparison",
                "fresh_sample_available must compare current and consumed generation",
            )
        )

    fresh_blocks = [
        block
        for block in main_if_blocks
        if _has_token(block.condition, "fresh_sample_available")
    ]
    if len(fresh_blocks) != 1:
        issues.append(
            ValidationIssue(
                "fresh-control-guard",
                "main() must have exactly one fresh_sample_available control guard",
            )
        )
    else:
        fresh_block = fresh_blocks[0]
        if not _has_token(fresh_block.body, "ControlPipeline_100HzFreshSample"):
            issues.append(
                ValidationIssue(
                    "fresh-pipeline-call",
                    "fresh branch must call ControlPipeline_100HzFreshSample",
                )
            )
        consumed_rhs = _assignment_rhs(
            fresh_block.body, r"\blast_controlled_sample_generation"
        )
        if consumed_rhs != ["imu_sample_generation"]:
            issues.append(
                ValidationIssue(
                    "fresh-generation-consume",
                    "fresh branch must consume the current generation exactly once",
                )
            )
        if fresh_block.else_body is None or not _has_token(
            fresh_block.else_body, "ControlPipeline_RejectStaleSample"
        ):
            issues.append(
                ValidationIssue(
                    "stale-failsafe",
                    "non-fresh branch must call ControlPipeline_RejectStaleSample",
                )
            )

    pipeline_function = functions.get("ControlPipeline_100HzFreshSample")
    if pipeline_function is None:
        issues.append(
            ValidationIssue(
                "pipeline-wrapper-missing",
                "ControlPipeline_100HzFreshSample definition not found",
            )
        )
    else:
        for api in sorted(PIPELINE_APIS):
            if not _has_token(pipeline_function.body, api):
                issues.append(
                    ValidationIssue(
                        "pipeline-wrapper-incomplete",
                        f"fresh pipeline wrapper does not call {api}",
                    )
                )

    stale_function = functions.get("ControlPipeline_RejectStaleSample")
    stale_reachable = _reachable_function_text(
        "ControlPipeline_RejectStaleSample", functions
    )
    if stale_function is None or not _has_token(
        stale_reachable, "STM32_TB6612_HAL_ForceSafe"
    ):
        issues.append(
            ValidationIssue(
                "stale-wrapper-unsafe",
                "stale-sample wrapper must directly force the HAL safe",
            )
        )

    return issues


def validate_motor_main(path: Path = DEFAULT_MAIN) -> list[ValidationIssue]:
    if not path.is_file():
        return [ValidationIssue("main-file-missing", f"missing canonical main: {path}")]
    return validate_motor_main_source(path.read_text(encoding="utf-8"))


def validate_shadow_main_source(source: str) -> list[ValidationIssue]:
    """Validate motor-off invariants inside the sealed historical 0822 file."""

    issues: list[ValidationIssue] = []
    clean = strip_c_comments_and_literals(source)
    authority_rhs = _assignment_rhs(clean, r"\bsuppression_start_allowed")
    if not authority_rhs or any(rhs not in {"0", "0U", "0u"} for rhs in authority_rhs):
        issues.append(
            ValidationIssue(
                "shadow-authority-not-locked",
                "every shadow suppression_start_allowed assignment must be zero",
            )
        )

    functions = extract_functions(clean)
    main_function = functions.get("main")
    if main_function is None:
        issues.append(
            ValidationIssue("shadow-main-missing", "0822 main() definition not found")
        )
    else:
        if _has_token(main_function.body, "Actuator_StateMachine_Update"):
            issues.append(
                ValidationIssue(
                    "shadow-actuator-update",
                    "0822 shadow main must never call Actuator_StateMachine_Update",
                )
            )
        if not _has_token(main_function.body, "Actuator_StateMachine_Reset"):
            issues.append(
                ValidationIssue(
                    "shadow-reset-missing",
                    "0822 shadow main must continually reset the actuator",
                )
            )

    uart_rhs = _assignment_rhs(clean, r"\bmotorEnabledForApp")
    derived_uart_rhs = [
        rhs
        for rhs in uart_rhs
        if _has_token(rhs, "motor_applied_state")
        and _has_token(rhs, "MOTOR_STOP")
    ]
    unexpected_uart_rhs = [
        rhs
        for rhs in uart_rhs
        if rhs not in {"0", "0U", "0u"} and rhs not in derived_uart_rhs
    ]
    if len(derived_uart_rhs) != 1 or unexpected_uart_rhs:
        issues.append(
            ValidationIssue(
                "shadow-uart-motor-semantics",
                "0822 UART status must derive from applied motor state, not gate state",
            )
        )
    return issues


def _git_blob_sha1(content: bytes) -> str:
    header = f"blob {len(content)}\0".encode("ascii")
    return hashlib.sha1(header + content).hexdigest()


def validate_shadow_blob(
    content: bytes, expected_hash: str
) -> list[ValidationIssue]:
    actual_hash = _git_blob_sha1(content)
    if actual_hash == expected_hash:
        return []
    return [
        ValidationIssue(
            "shadow-seal-mismatch",
            f"0822 sealed blob changed: expected {expected_hash}, got {actual_hash}",
        )
    ]


def validate_shadow_main(
    path: Path = DEFAULT_SHADOW_MAIN,
    manifest_path: Path = DEFAULT_MANIFEST,
) -> list[ValidationIssue]:
    if not path.is_file():
        return [ValidationIssue("shadow-file-missing", f"missing shadow main: {path}")]
    try:
        manifest = load_manifest(manifest_path)
        expected_hash = manifest["sealed_shadow_reference"]["git_blob_sha1"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        return [ValidationIssue("shadow-seal-unreadable", str(exc))]
    content = path.read_bytes()
    issues = validate_shadow_blob(content, expected_hash)
    issues.extend(validate_shadow_main_source(content.decode("utf-8")))
    return issues


def _print_issues(label: str, issues: Iterable[ValidationIssue]) -> int:
    materialized = list(issues)
    if not materialized:
        print(f"PASS {label}")
        return 0
    print(f"FAIL {label}")
    for issue in materialized:
        print(f"  [{issue.code}] {issue.message}")
    return len(materialized)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main", type=Path, default=DEFAULT_MAIN)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--shadow-main", type=Path, default=DEFAULT_SHADOW_MAIN)
    parser.add_argument(
        "--skip-shadow", action="store_true", help="skip the 0822 motor-off check"
    )
    args = parser.parse_args(argv)

    failures = 0
    failures += _print_issues(
        "authoritative module manifest", validate_manifest(args.manifest)
    )
    failures += _print_issues(str(args.main), validate_motor_main(args.main))
    if not args.skip_shadow:
        failures += _print_issues(
            str(args.shadow_main),
            validate_shadow_main(args.shadow_main, args.manifest),
        )
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
