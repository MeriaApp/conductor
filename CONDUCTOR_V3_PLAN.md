# Conductor v3.0 — "Invisible Intelligence Made Visible"

*Created: March 8, 2026*

## Overview
Conductor does 50 things but doesn't communicate the 3 that matter. This plan surfaces the invisible value, simplifies the chrome, and makes multi-agent practical.

---

## Item 1: Savings Tracker — "Conductor saved you ~$X.XX"
**Status: DONE**
**Effort: Low**
**Files:** ClaudeProcess.swift, StatusBar.swift

Track cumulative savings from:
- Effort downgrades (high→medium = ~30% savings on that turn, high→low = ~50%)
- Model switches (Opus→Sonnet = ~80% savings, Opus→Haiku = ~95%)
- Skipped closeouts (each skip = ~$0.50-2.00 saved)

Display: subtle text in status bar near cost: "$4.21 (saved ~$2.80)"

---

## Item 2: Compaction Toast — "Context compacted — 5 decisions, 12 files preserved"
**Status: DONE**
**Effort: Low**
**Files:** ContextPreservationPipeline.swift, AppShell.swift (toast view)

When compaction is detected:
1. Count preserved items (decisions, files, constraints)
2. Show a 4-second auto-dismissing toast at top of conversation
3. One line: "Context compacted — X decisions, Y files preserved"
4. Builds trust that Conductor is protecting context

---

## Item 3: Simplified Status Bar — 3-Zone Layout
**Status: DONE**
**Effort: Low**
**Files:** StatusBar.swift

Reorganize into 3 zones:
- **Left:** Model + Context% + Cost (checked every turn)
- **Center:** Working dir + Git branch (project context)
- **Right:** Effort + Permission + Luminance (rarely changed settings)

Hide until relevant (only show when non-default):
- Output mode (hidden when "Standard")
- Agent teams (hidden when off) — already done
- Budget indicator — show only when budget >80% used OR explicitly set to non-default

---

## Item 4: Practical Multi-Agent — One-Click Presets
**Status: DONE**
**Effort: Medium**
**Files:** AgentOrchestrator.swift, AgentPresets.swift, CommandPalette.swift, AppShell.swift

### 4a: One-Click Presets in Command Palette
Add 3 preset workflows:
- "Audit Codebase" → spawns Researcher + Reviewer + Reporter (swarm pattern)
- "Build & Test" → spawns Builder + Tester (pipeline pattern)
- "Parallel Research" → spawns 2-3 Researchers (swarm pattern)

Each preset auto-configures agents with appropriate roles, effort levels, and initial tasks.

### 4b: Results Synthesis
When all agents in a preset finish, auto-generate unified summary:
- Collect final messages from each agent
- Present as a single "Team Report" message in main conversation
- Format: "## Agent Results\n### Researcher\n...\n### Reviewer\n..."

---

## Item 5: Direct API Backend (Monetization Unlock)
**Status: DEFERRED — separate session**
**Effort: High**

This is a major architectural change (new API client, streaming, tool use parsing, auth/key management). Deferring to dedicated session.

---

## Execution Order
1. Item 1 (savings tracker)
2. Item 2 (compaction toast)
3. Item 3 (status bar simplification)
4. Item 4 (multi-agent presets)
5. Build + verify all changes compile
6. Update CONTEXT_STATE.md
