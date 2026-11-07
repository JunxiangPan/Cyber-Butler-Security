@echo on
setlocal
cd /d "C:\CyberButler"
set "PYTHONPATH=C:\CyberButler;C:\CyberButler/tools;C:\CyberButler\python\Lib\site-packages"
if not exist "C:\CyberButler\python\python.exe" (
  echo FALLBACK ERROR: portable python missing
  pause
  exit /b 1
)
if not exist "C:\CyberButler\tools\broker.py" (
  echo FALLBACK ERROR: broker.py missing
  pause
  exit /b 1
)
"C:\CyberButler\python\python.exe" "C:\CyberButler\tools\broker.py"
set "EXITCODE=%ERRORLEVEL%"
echo FALLBACK broker exit code=%EXITCODE%
pause
exit /b %EXITCODE%
