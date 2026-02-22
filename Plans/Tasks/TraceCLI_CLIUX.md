Prompt:
Implement the terra CLI UX for trace serving, print, and doctor commands per the plan, wiring flags and startup instructions.

Goal:
Provide a demo-ready CLI surface area with clear guidance for simulator and device setup, and stable output formats driven by TerraTraceKit.

Task Breakdown:
1. Add `terra trace serve` command with flags: host, port, bind-all, format, print-every, filter name prefix, and filter traceId.
2. Print startup instructions that include simulator and physical device endpoint guidance and mention binding to 0.0.0.0 for devices.
3. Wire serve command to start the receiver and render output in stream or tree format on the specified cadence.
4. Add `terra trace print` scaffolding for v1.1 with inputs (otlp-file or jsonl) and format tree|json, even if no implementation beyond CLI parsing is done yet.
5. Add `terra trace doctor` command that outputs troubleshooting checklist: simulator endpoint, device endpoint, and no-spans checklist.
6. Ensure flags and help text are concise, Swifty, and hard to misuse.

Expected Output:
- CLI commands and flags implemented in the terra executable target.
- Clear startup and doctor guidance consistent with the plan.
- Serve command wired to receiver and renderers with print cadence.
- No plan edits; no implementation beyond CLI UX.
