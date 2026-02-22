Prompt:
Implement Feature B (span list keyboard navigation) to satisfy tests.
Goal:
Provide command/focus-based keyboard navigation that updates selection and keeps it within bounds.
Task Breakdown:
- Add keyboard command handlers or focus-based actions in the span list view.
- Update view model selection based on navigation actions.
- Ensure selection updates drive detail sync as tested.
- Enforce type safety and keep API surface minimal.
Expected Output:
- Updated view(s)/view model(s) implementing keyboard navigation.
- Tests from Feature B pass.
