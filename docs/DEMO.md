# Recording the demo

The repo ships a safe, read-only tour in [`demo.sh`](demo.sh). Recording it into a
GIF is a **manual step** — it needs a real terminal, so it can't be generated in CI
or checked in automatically. Here's the exact flow.

## 1. Preview the tour

```bash
bash docs/demo.sh          # every step is read-only: no root, no writes
bash docs/demo.sh -h       # what it does
```

## 2. Record a cast with [asciinema](https://asciinema.org/)

```bash
# install: pipx install asciinema   (or: sudo apt install asciinema)
asciinema rec docs/demo.cast -c "bash docs/demo.sh"
```

This writes `docs/demo.cast` (a small text file — safe to commit).

## 3. Convert the cast to a GIF with [agg](https://github.com/asciinema/agg)

```bash
# install: cargo install --git https://github.com/asciinema/agg
agg docs/demo.cast docs/demo.gif
```

## 4. Embed it in the README

```markdown
![demo](docs/demo.gif)
```

Put that near the top of `README.md`, under the badges.

> **Note:** neither artifact is checked in — generate them locally. The `.cast` is small
> plain text and fine to commit if you want it; the `.gif` is large and binary, so keep it
> out of history unless you specifically want it rendered in the README.
