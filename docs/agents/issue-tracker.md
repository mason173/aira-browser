# Issue tracker: GitHub

Issues, specs, and implementation tickets for this repository live as GitHub Issues. Use the `gh` CLI from inside the clone so it infers `mason173/Aira-browser` from the configured remote.

## Conventions

- Create an issue with `gh issue create`.
- Read an issue and its discussion with `gh issue view <number> --comments`.
- List and filter work with `gh issue list` and JSON output when structured inspection is needed.
- Comment with `gh issue comment`; update labels with `gh issue edit`.
- Apply `ready-for-agent` to a fully specified issue that an agent can complete without unstated human context.
- Do not close or modify a parent issue when publishing child implementation tickets.

## Pull requests as a triage surface

External pull requests are not a triage request surface. Issues are the only request queue configured for the engineering skills.

## Publishing and dependencies

When a skill says to publish a spec or ticket, create a GitHub Issue. Publish blocker tickets first, then dependents. Prefer GitHub native issue dependencies for blocking edges; if the repository does not expose them, record `Blocked by: #<number>` in the dependent issue body. A ticket is on the work frontier only when every blocking issue is closed and it is not already assigned.
