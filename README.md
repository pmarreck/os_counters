# os_counters

Cross-process **atomic counters** for the shell, implemented in [LuaJIT](https://luajit.org/),
with three interchangeable backends that make different OS-level tradeoffs. They share one
CLI (`create` / `get` / `inc` / `dec` / `set` / `destroy` / `list`), so you can pick the
backend that fits your platform and durability needs.

```sh
counter create hits 0     # counter == fs-counter (the default backend)
counter inc hits          # -> 1
counter inc hits          # -> 2
counter get hits          # -> 2
counter destroy hits
```

## Backends & platform tradeoffs

| Backend | Mechanism | macOS | Linux | sudo? | Notes |
|---|---|---|---|---|---|
| **`fs-counter`** (default, = `counter`) | file + `flock` locking under `$FS_COUNTER_DIR` (def. `${TMPDIR:-/tmp}/fs-counter`) | ✅ full | ✅ full | no | only backend with `list` + heavy concurrency coverage; portable |
| **`posix-counter`** | POSIX shm (`shm_open`/`mmap`) | ⚠️ limited | ✅ | no | see macOS note |
| **`sysv-counter`** | System V IPC (`shmget`/`shmat`) | ⚠️ needs sudo | ✅ | yes (macOS) | capped by `kern.sysv.shmmax` (4 MB default) |

These are real, current OS limitations (still present as of 2026), not implementation bugs:

- **System V shm on macOS** caps a segment at **4 MB** by default (`kern.sysv.shmmax`,
  tunable only via `sudo sysctl -w kern.sysv.shmmax=…`), and attaching needs elevated
  privileges — hence `sysv-counter` requires `sudo` on macOS. On Linux it works unprivileged.
- **POSIX shm on macOS** has a long-standing quirk: `ftruncate()` on a `shm_open` object
  **only succeeds once** (subsequent calls fail with `EINVAL`), and there is no `/dev/shm`.
  That makes `posix-counter` unreliable on macOS, so it is **not** the default.
- **Filesystem locking** has none of these constraints, which is why `fs-counter` is the
  portable default.

Sources: [shared memory on Linux & macOS](https://www.deepanseeralan.com/tech/playing-with-shared-memory/),
[posix_ipc #5 — ftruncate once on macOS](https://github.com/osvenskan/posix_ipc/issues/5),
[darwin-kernel: shm_open/mmap EINVAL](https://lists.apple.com/archives/darwin-kernel/2005/Feb/msg00079.html).

## Install

### Nix (flake)

```sh
nix run github:pmarreck/os_counters -- create hits 0   # runs `counter` (fs backend)
nix profile install github:pmarreck/os_counters
```

### Manual

Put `bin/` on your `PATH` (contains `fs-counter`, `posix-counter`, `sysv-counter`, and the
`counter`→`fs-counter` symlink). `fs-counter` loads `lib/truthy.lua` relative to itself, so
keep `bin/` and `lib/` siblings. Requires `luajit` on `PATH`.

## Development

```sh
direnv allow      # or: nix develop
./test                      # fs backend (default) — quick, no sudo
COUNTER_TYPE=posix ./test   # posix backend (best on Linux)
COUNTER_TYPE=sysv  ./test   # sysv backend; SKIPS cleanly if passwordless sudo is unavailable
nix flake check             # hermetic CI check (fs backend only — what Garnix runs)
```

The `sysv` suite uses `sudo -n` and **skips cleanly (exit 0) rather than ever prompting for
a password**, so unattended runs never hang. CI only exercises the `fs` backend because the
sandbox has no sudo and POSIX/SysV shm behave differently there.

## Layout

```
bin/fs-counter        filesystem-locking backend (the default)
bin/posix-counter     POSIX shared-memory backend
bin/sysv-counter      System V IPC backend
bin/counter           -> fs-counter
lib/truthy.lua        small shared helper required by fs-counter
tests/counter_test    unified suite, parameterized by $COUNTER_TYPE
tests/{fs,posix,sysv}*_test  thin wrappers that set COUNTER_TYPE and exec counter_test
flake.nix             dev shell, package, and CI check
test                  test runner
```

## License

MIT © Peter Marreck
