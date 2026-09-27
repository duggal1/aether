<!-- INIT-RULES:START — do not remove this marker. Managed by `init rules`. -->
> [!IMPORTANT]
> **Strictly and forcefully read `./RULES.md` BEFORE doing anything else — and stay fully aligned with it for the entire task.**
>
> **Scope: RULES.md applies to real, complex work — especially complex back-end work (features, architecture, database/migrations, security, performance, infrastructure, difficult debugging, cross-system changes, and anything where testing/verification is part of the core workflow). This is mandatory there — no skipping.**
>
> **Out of scope: do NOT apply RULES.md ceremony to super-simple front-end minor edits, small code edits, typo/copy fixes, trivial styling tweaks, or other tiny low-risk changes. For those, just inspect → edit → verify.**
<!-- INIT-RULES:END -->

# MANDATORY ENGINEERING PRINCIPLE: NEVER OVERENGINEER. NEVER UNDERENGINEER.

**Your objective is to build the most modern, reliable, performant, production-grade architecture with the MINIMUM UNNECESSARY COMPLEXITY, not the minimum complexity overall.**

This distinction is ABSOLUTELY NON-NEGOTIABLE.

### 1. Essential Complexity Is NOT Overengineering

Some products are inherently complex. A production-grade AI-native browser, for example, requires sophisticated rendering, navigation, concurrency, process isolation, lifecycle management, memory management, asynchronous execution, and fault recovery.

**If the problem inherently requires complexity, IMPLEMENT THAT COMPLEXITY FULLY AND CORRECTLY.**

Never simplify away essential functionality, architectural boundaries, reliability mechanisms, or performance-critical engineering merely to make the code shorter or architecture appear simpler.

Never replace a necessary sophisticated system with a primitive implementation that cannot satisfy the actual requirements.

**DO NOT UNDERENGINEER COMPLEX PROBLEMS. DO NOT OVERENGINEER SIMPLE PROBLEMS.**

### 2. Eliminate Accidental Complexity, Preserve Essential Complexity

Your responsibility is to distinguish between:

- **Essential complexity:** Complexity inherently required by the product, operating system, performance constraints, concurrency, security, correctness, or real-world functionality. IMPLEMENT IT PROPERLY.
- **Accidental complexity:** Unnecessary abstractions, duplicated systems, excessive layers, speculative infrastructure, redundant dependencies, convoluted execution paths, and architectures more complicated than the actual requirements demand. ELIMINATE IT.

Never confuse sophisticated engineering with overengineering.

Never confuse fewer lines of code with better architecture.

### 3. Mandatory Planning and Execution

For minor, straightforward changes, fix them directly without creating unnecessary plans.

For substantive backend issues, architectural changes, complex bugs, and performance problems:

1. Inspect the actual implementation and establish the verified root cause.
2. Identify ALL real technical requirements and constraints.
3. Create a precise, non-ambiguous, evidence-based implementation plan.
4. Determine which architectural complexity is genuinely necessary.
5. Choose the most modern, reliable architecture that satisfies every requirement without unnecessary complexity.
6. Execute the plan completely.
7. Verify correctness, reliability, and actual runtime performance.

Never fabricate root causes or assume an architectural change is beneficial without evidence.

### 4. Never Compound Failed Architecture

If an approach fails, investigate the root cause. Fix it properly.

If the underlying approach is fundamentally unsuitable, replace it with a technically superior architecture rather than accumulating patches and workarounds.

Do not replace a sound architecture merely because its implementation contains a fixable bug.

**FINAL ABSOLUTE RULE:**

Build exactly as much architectural sophistication as the REAL PROBLEM requires.

If the correct solution is simple, make it simple.

If the correct solution is inherently complex, implement its FULL necessary complexity without hesitation.

If a simpler architecture achieves identical correctness, reliability, performance, and functionality, prefer it.

**NEVER OVERENGINEER. NEVER UNDERENGINEER. NEVER SACRIFICE ESSENTIAL COMPLEXITY. ELIMINATE ONLY UNNECESSARY COMPLEXITY.**

The goal is not simple software at any cost.

**The goal is the simplest architecture capable of correctly delivering the FULL complexity of the actual product.**