#!/bin/sh
# 套件内共用设施；仅在测试进程中 source，所有命令由被测 BusyBox ash 提供。
bbtest_init() {
  BBTEST_START=$(pwd -P) || exit 2
  BBTEST_SEQ=0
  BBTEST_TRY=0
  while [ "$BBTEST_TRY" -lt 20 ]; do
    TEST_ROOT="$BBTEST_START/busybox-test-$1-$$-$BBTEST_TRY"
    if mkdir "$TEST_ROOT" 2>/dev/null; then
      trap bbtest_cleanup 0
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      cd "$TEST_ROOT" || exit 2
      return 0
    fi
    BBTEST_TRY=$((BBTEST_TRY + 1))
  done
  echo "无法创建测试目录（只尝试 20 次）: $BBTEST_START" >&2
  exit 2
}

bbtest_cleanup() {
  BBTEST_EXIT=$?
  trap - 0
  cd "$BBTEST_START" || exit 2
  if [ "${KEEP_TEST_ROOT:-0}" = 1 ]; then
    echo "测试目录已保留: $TEST_ROOT" >&2
  else
    # Windows 上刚退出的子进程/重定向句柄可能短暂阻止目录删除。
    # 有界重试既吸收这种关闭竞态，也避免永久锁定时无限等待。
    BBTEST_CLEAN_TRY=0
    while ! rm -rf "$TEST_ROOT" 2>/dev/null; do
      BBTEST_CLEAN_TRY=$((BBTEST_CLEAN_TRY + 1))
      if [ "$BBTEST_CLEAN_TRY" -ge 5 ]; then
        echo "测试目录清理失败（已重试 $BBTEST_CLEAN_TRY 次）: $TEST_ROOT" >&2
        [ "$BBTEST_EXIT" -ne 0 ] && exit "$BBTEST_EXIT"
        exit 2
      fi
      sleep 1
    done
  fi
  exit "$BBTEST_EXIT"
}

# 调用命令在子 shell 中运行，防止测试修改 cwd/trap/变量污染下一项。
# bbtest_try 只捕获结果，供允许失败的能力探测使用。
bbtest_try() {
  BBTEST_SEQ=$((BBTEST_SEQ + 1))
  BBTEST_LOG="$TEST_ROOT/case-$BBTEST_SEQ.log"
  BBTEST_RC=0
  ( "$@" ) >"$BBTEST_LOG" 2>&1 || BBTEST_RC=$?
  return "$BBTEST_RC"
}

# 硬断言失败时把捕获日志送入 CI；清理临时目录不会吞掉诊断。
bbtest_run() {
  if bbtest_try "$@"; then
    return 0
  else
    BBTEST_RC=$?
  fi
  echo "--- 用例 $BBTEST_SEQ 失败，退出码 $BBTEST_RC ---" >&2
  cat "$BBTEST_LOG" >&2
  return "$BBTEST_RC"
}
