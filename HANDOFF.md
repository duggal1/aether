# Handoff to the next AI agent

## Architecture Clarification

**This is critical: Aether uses Apple WebKit for web rendering, not a custom rendering engine.**

### Two-Layer Architecture

**Layer 1: Rendering (WebKit)**
- Apple's WebKit (`WKWebView`) handles all HTML, CSS, JavaScript rendering
- Production web content display uses WebKit exclusively
- WebKit manages web security, process isolation, and platform APIs
- Do not replace, modify, or rebuild WebKit's rendering capabilities

**Layer 2: Browser Runtime (Custom)**
- Aether's custom engine provides:
  - Browser runtime state (tabs, navigation, profiles, contexts)
  - Agent control protocol (76 methods via `browserctl`/`browserd`)
  - Structured page data for agents (DOM inspection, element geometry, navigation state)
  - Cookie management, storage, content blocking
  - Session management and fleet scheduling
- Custom engine modules (HTML, CSS, Style, Layout, etc.) support agent-facing operations
- These modules enable structured intelligence beyond what WebKit exposes

### What This Means

**We are NOT:**
- Building another HTML/CSS rendering engine
- Replacing WebKit
- Reimplementing web standards for rendering

**We ARE:**
- Building a browser runtime that agents can control programmatically
- Providing structured access to page data (DOM, geometry, state)
- Optimizing agent operations (fast DOM queries, efficient state management)
- Extending WebKit's capabilities for agent control where APIs allow

## Current State

The repository contains:
- WebKit integration (`Sources/EngineRuntime/WebKit/`) - production rendering
- Custom browser runtime (`EngineRuntime`) - tabs, navigation, profiles, agent protocol
- Agent protocol (`AgentProtocol`) - 76 methods for agent control
- Native macOS UI (`Sources/BrowserUI/`) - SwiftUI interface
- Content blocking, storage, networking, diagnostics modules
- Unix-socket daemon (`browserd`) and CLI (`browserctl`)

## Priorities

1. **Run `swift test`, release build, and benchmarks** before changing behavior
2. **Optimize agent operations** - fast DOM queries, efficient state management, low-overhead protocol
3. **Deepen agent-facing capabilities** - better DOM inspection, element geometry, JavaScript execution, navigation state
4. **Improve browser runtime performance** - tab management, session handling, fleet scheduling
5. **Enhance security and isolation** - respect WebKit's security model, add runtime safeguards
6. **Optimize memory and GPU usage** - efficient state management, leverage WebKit's Metal rendering
7. **Expand agent protocol** - add missing capabilities within WebKit's API constraints
8. **Improve testing** - cover agent workflows, integration tests, performance benchmarks

## What NOT To Do

- Do not add a chatbot or cloud control plane
- Do not replace WebKit or rebuild rendering capabilities
- Do not remove existing browser infrastructure
- Do not break the agent protocol or UI
- Do not claim capabilities that WebKit doesn't provide

## Key Principle

The external AI agent (Claude Code, Codex, OpenCode) decides what to do. Aether provides:
- A clean, fast browser runtime
- Structured access to page data
- Deterministic agent control
- Integration with WebKit's rendering

Your job is to optimize the agent control layer and browser runtime, not rebuild web rendering.

Keep `AGENTS.md` as the operating contract. Preserve small public APIs, one-way dependencies, bounded state, and truthful scope.
