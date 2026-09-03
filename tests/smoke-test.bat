@echo off
rem ============================================================
rem  busybox APE Windows 冒烟测试入口
rem  用法: 把 busybox.com + smoke.sh + smoke-test.bat 放同一目录
rem        双击或 cmd 执行 smoke-test.bat
rem  结果: 输出到 smoke-results.txt 与控制台
rem ============================================================
setlocal
set OUT=smoke-results.txt
cd /d %~dp0

if not exist busybox.com (
  echo [ERROR] busybox.com not found in %cd%
  exit /b 1
)
if not exist smoke.sh (
  echo [ERROR] smoke.sh not found in %cd%
  exit /b 1
)

echo running: busybox.com sh smoke.sh ...
busybox.com sh smoke.sh > %OUT% 2>&1
set RC=%ERRORLEVEL%

type %OUT%
echo.
echo ============================================
echo  results written to %cd%\%OUT%
echo  (exit code %RC%; 0 = 关键路径全 PASS)
echo ============================================
exit /b %RC%
