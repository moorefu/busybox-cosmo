# [cosmopolitan upstream issue draft] apeinstall.sh should register P flag on kernels < 5.12

**Repo**: jart/cosmopolitan — ape/apeinstall.sh

## Summary

`ape/apeinstall.sh` only registers binfmt_misc with the `P` (preserve-argv[0])
flag on kernels >= 5.12 (`FLAGS=FP`), using plain `F` below that. On kernels
< 5.12 (verified: Linux 4.19 aarch64, UOS/麒麟), **APE programs run fine at
top level but every nested exec loses argv[0]**, breaking shells and applet
re-exec:

```
$ busybox-fat.ape sh -c 'wc -c < /dev/null'
-c: applet not found        # argv[0]="wc" was dropped; "-c" (a real arg) became argv[0]
$ busybox-fat.ape sh -c 'echo a | grep a'
a: applet not found
```

The binfmt_misc `P` flag itself is ancient; the 5.12 boundary only matters for
the auxv notification (`AT_FLAGS_PRESERVE_ARGV0`, commit 2347961b11d4), which
the loader uses for its `arg0` fast path. Registering `P` on 4.19 **works and
is required** for correct argv semantics (the loader's default path handles it):

```
# before (4.19, flag F):        nested exec broken
# after  (4.19, flag FP):       all tests pass
$ ./busybox-fat.ape sh -c 'wc -c < /dev/null'; echo $?   # → 0
$ ./busybox-fat.ape sh -c 'echo a | grep a'              # → a
```

## Suggested fix

```sh
# apeinstall.sh: drop the 5.12 gate; P is safe & needed on older kernels too
# (5.12+ additionally benefits from the auxv notify path)
FLAGS=FP
```

## Environment

- Linux 4.19.90 aarch64 (UOS Server 20, 64KB pages — unrelated to this bug)
- ape loader: master build (loader.c default path)
- Repro: any APE with a shell: `./prog sh -c 'grep -c . </dev/null'` on kernel < 5.12 with flag `F` registration
