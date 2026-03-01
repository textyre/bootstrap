# CI Tracking PRs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run full CI suite for all roles, then create one tracking PR per failing role with the CI output as the PR description.

**Architecture:** Trigger `workflow_dispatch` on `molecule.yml` with `role_filter=all`. Poll until complete. For each failing role, a worker agent in a worktree creates an empty-commit branch and opens a PR whose body contains the failure log extracted via `gh run view --log-failed`.

**Tech Stack:** GitHub Actions, `gh` CLI, git worktrees, beast-mode agents (one per failing role)

---

### Task 1: Trigger full CI run

**Files:** none

**Step 1: Trigger dispatch**

```bash
gh workflow run molecule.yml -f role_filter=all
```

**Step 2: Capture the new run ID**

```bash
# Wait ~5s for GitHub to register the run, then grab the latest dispatch run ID
sleep 5
RUN_ID=$(gh run list --workflow=molecule.yml --event=workflow_dispatch --limit=1 --json databaseId --jq '.[0].databaseId')
echo "Run ID: $RUN_ID"
```

Expected: prints a numeric run ID.

---

### Task 2: Wait for CI completion

**Step 1: Poll until done**

```bash
while true; do
  STATUS=$(gh run view $RUN_ID --json status,conclusion --jq '{status,conclusion}')
  echo "$(date -u +%H:%M:%S) $STATUS"
  DONE=$(echo "$STATUS" | jq -r '.status')
  [ "$DONE" = "completed" ] && break
  sleep 60
done
echo "CI finished: $(gh run view $RUN_ID --json conclusion --jq '.conclusion')"
```

Expected: lines of status updates until "completed".

---

### Task 3: Collect failing roles

**Step 1: Extract all failed job names**

```bash
gh run view $RUN_ID --json jobs \
  --jq '[.jobs[] | select(.conclusion == "failure") | .name]'
```

**Step 2: Parse into per-role failure map**

Script logic (parse job names like `"test (locale) / locale (Arch+Ubuntu/systemd)"`,
`"test-vagrant (locale, arch-vm) / locale — arch-vm"`,
`"test-vagrant (locale, ubuntu-base) / locale — ubuntu-base"`):

```bash
# Docker failures
DOCKER_FAIL=$(gh run view $RUN_ID --json jobs \
  --jq '[.jobs[] | select(.conclusion=="failure" and (.name | test("^test \\("))) | .name | capture("test \\((?P<role>[^)]+)\\)").role] | unique | .[]')

# Vagrant arch failures
ARCH_FAIL=$(gh run view $RUN_ID --json jobs \
  --jq '[.jobs[] | select(.conclusion=="failure" and (.name | test("test-vagrant .*, arch-vm"))) | .name | capture("test-vagrant \\((?P<role>[^,]+),").role] | unique | .[]')

# Vagrant ubuntu failures
UBUNTU_FAIL=$(gh run view $RUN_ID --json jobs \
  --jq '[.jobs[] | select(.conclusion=="failure" and (.name | test("test-vagrant .*, ubuntu-base"))) | .name | capture("test-vagrant \\((?P<role>[^,]+),").role] | unique | .[]')

# Union of all failing roles
ALL_FAIL=$(echo -e "$DOCKER_FAIL\n$ARCH_FAIL\n$UBUNTU_FAIL" | sort -u | grep -v '^$')
echo "Failing roles:"
echo "$ALL_FAIL"
```

**Step 3: For each role, record which tests failed**

```bash
# Build per-role summary (used later for PR body)
for ROLE in $ALL_FAIL; do
  DOCKER=""; ARCH=""; UBUNTU=""
  echo "$DOCKER_FAIL" | grep -q "^${ROLE}$" && DOCKER="❌ Docker"
  echo "$ARCH_FAIL"   | grep -q "^${ROLE}$" && ARCH="❌ Vagrant arch-vm"
  echo "$UBUNTU_FAIL" | grep -q "^${ROLE}$" && UBUNTU="❌ Vagrant ubuntu-base"
  echo "$ROLE: $DOCKER $ARCH $UBUNTU"
done
```

---

### Task 4: Per-role — create tracking PR (one agent per role, run in parallel)

For each failing role, spawn a **beast-mode agent** (as a background agent via Agent tool).

Each agent receives:
- Role name
- Which tests failed (docker/arch/ubuntu)
- Run ID (to fetch logs)
- Instructions below

**Agent instructions (template per role `$ROLE`):**

**Step 1: Create branch**

```bash
cd /Users/umudrakov/Documents/bootstrap
git fetch origin master
git checkout -b ci/track-$ROLE origin/master
```

**Step 2: Create empty commit**

```bash
git commit --allow-empty -m "ci($ROLE): track CI failures [WIP]

Run: https://github.com/textyre/bootstrap/actions/runs/$RUN_ID"
```

**Step 3: Push**

```bash
git push origin ci/track-$ROLE
```

**Step 4: Fetch CI failure log for the role**

For each failing test type, get the relevant job log:

```bash
# Docker log (if failed)
DOCKER_LOG=$(gh run view $RUN_ID --log-failed 2>/dev/null \
  | grep -A 200 "test ($ROLE)" | head -150)

# Vagrant arch log (if failed)
ARCH_LOG=$(gh run view $RUN_ID --log-failed 2>/dev/null \
  | grep -A 200 "test-vagrant ($ROLE, arch-vm)" | head -150)

# Vagrant ubuntu log (if failed)
UBUNTU_LOG=$(gh run view $RUN_ID --log-failed 2>/dev/null \
  | grep -A 200 "test-vagrant ($ROLE, ubuntu-base)" | head -150)
```

**Step 5: Create PR**

```bash
gh pr create \
  --title "ci($ROLE): fix failing molecule tests" \
  --base master \
  --head ci/track-$ROLE \
  --body "$(cat <<'EOF'
## CI Failures — $ROLE

From run: https://github.com/textyre/bootstrap/actions/runs/$RUN_ID

### Failed tests

| Test | Result |
|------|--------|
| Docker (Arch+Ubuntu/systemd) | $DOCKER_STATUS |
| Vagrant arch-vm | $ARCH_STATUS |
| Vagrant ubuntu-base | $UBUNTU_STATUS |

### Docker failure log
<details><summary>Expand</summary>

\`\`\`
$DOCKER_LOG
\`\`\`
</details>

### Vagrant arch-vm failure log
<details><summary>Expand</summary>

\`\`\`
$ARCH_LOG
\`\`\`
</details>

### Vagrant ubuntu-base failure log
<details><summary>Expand</summary>

\`\`\`
$UBUNTU_LOG
\`\`\`
</details>
EOF
)"
```

---

### Task 5: Summary

After all agents complete:

- Collect all PR URLs from each agent
- Print a summary table: role → PR URL → which tests failed
- Update MEMORY.md with current known-failing roles

---

## Notes

- **Git policy:** Main agent cannot do git write ops. All git/push/pr operations happen inside beast-mode agents.
- **Concurrency:** All role agents run in parallel (Agent tool, `run_in_background=true` for all).
- **Worktrees:** Each agent uses `git checkout -b` on the main repo (not worktrees) since branches are independent and don't share files.
- **Log extraction:** `gh run view --log-failed` dumps all failed logs. Filter by job name. Logs may be large; truncate to 150 lines per job.
- **Empty commits:** `--allow-empty` is required since no code changes are made. These are pure tracking PRs.
