# Valheim Behavior Parity

The authoritative comparison is the [September 30 audit](VALHEIM-PARITY-AUDIT-2026-09-30.md), based on Valheim public commit `b02b951` and Enshrouded's pre-fix `ab9e8a1` baseline.

The [implementation plan and outcome record](PARITY-IMPLEMENTATION-PLAN.md) maps every finding to its correction, evidence and remaining verification limits in the 0.1.9 candidate. The baseline audit deliberately remains unchanged after repairs.

Previous reliability work preserved useful installation, update, backup and packaging safeguards, but did not establish complete native interaction or background-service parity. A green unit-test count alone is not proof of the whole application experience.

Shared manager workflows follow Valheim. Enshrouded retains its Windows compatibility environment, native roles/rules/save format, irregular game-reported simulation metrics and supported administration capabilities. The user's explicit UI/history/scheduling preferences remain in force. See the dated audit for the complete rationale and exceptions.
