# Huawei Space Remote Reset Is Not An MVP User Action

Generalized to every sync provider by ADR 0033.

Accepted: Provider Remote Reset for Huawei Space Sync will not be exposed as an ordinary MVP user-facing action. Resetting the remote store discards tombstones, generations, and device/source history, so MVP should keep it to development or diagnostic recovery paths; a later user-facing reset needs dangerous-action confirmation, clear consequences, and preferably a local backup/export step.
