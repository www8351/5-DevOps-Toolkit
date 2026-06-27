# DECISIONS

The decision log. Why things are the way they are, and what was rejected.

---

### D1 — One shared library (`lib/common.sh`), not standalone scripts
**Decision:** Every script sources a single shared engine for logging, guards and the `run`/`confirm`
wrappers.
**Why:** Demonstrates DRY composition and keeps 24 tools consistent (identical flags and safety behaviour).
**Rejected:** Fully self-contained scripts — simpler to copy one file, but duplicates boilerplate 24× and
drifts over time.
**Status:** Final.

---

### D2 — "Real operational" scripts with hard safety guards
**Decision:** Scripts perform the actual operations (`useradd`, `docker run`, `mkswap`, `apt install`…),
but gate every destructive/root action behind `require_root` + `confirm`, and support `DRY_RUN=1`.
**Why:** The user explicitly chose real tools over safe demos; guards make "real" responsible instead of
dangerous.
**Rejected:** Pure echo/demo scripts (too toothless for a portfolio); raw unguarded commands (unsafe).
**Status:** Final.

---

### D3 — Group the command list into exactly 5 themed folders
**Decision:** files/text, users/permissions, system/hardware, network/ssh, docker/devops.
**Why:** Matches the natural clusters in the source cheat-sheet and the user's "5 folders" request; each
folder reads as a coherent mini-toolkit.
**Rejected:** One folder per command (too granular); a single flat folder (no narrative).
**Status:** Final.

---

### D4 — `ec2-deploy` written in Python, everything else in Bash
**Decision:** The AWS/boto3 deploy tool is Python; the other 23 tools are Bash.
**Why:** boto3 is a Python library — forcing it into Bash via the AWS CLI would be clumsier and less
faithful to the original `boto3` notes.
**Status:** Final.

---

### D5 — Bilingual (Hebrew + English) README, public repo
**Decision:** Root README carries side-by-side HE/EN intro; repo is public.
**Why:** User is Hebrew-speaking and wants a portfolio piece; bilingual widens the audience.
**Status:** Final.

---

### D6 — Keep the `CLAUDE.md` lifecycle files at the repo root
**Decision:** `STATUS.md` / `PROGRESS.md` / `DECISIONS.md` / `CLAUDE_MEMORY.md` live at root and are
committed.
**Why:** Mandated by the workspace `CLAUDE.md` protocol; they also signal disciplined process to anyone
reading the repo.
**Revisitable:** Could later move under `docs/` if they clutter the root — not blocking.

---

### D7 — Build via a parallel multi-agent workflow
**Decision:** One agent per folder wrote that folder's scripts + README, each followed by a review agent.
**Why:** 5 disjoint folders parallelise cleanly; the review pass catches contract violations before commit.
**Status:** Final for v1.
