@echo off
title SemaiKu AI Server - Deteksi Pakcoy
color 0A
cls
echo ========================================================================
echo   🌿 SISTEM MONITORING & DETEKSI AI SEMAIKU (LAPTOP SERVER)
echo ========================================================================
echo.
echo Mencari alamat IP Wi-Fi laptop Anda...
for /f "tokens=4" %%a in ('route print 0.0.0.0 ^| findstr 0.0.0.0 ^| findstr /v "0.0.0.0.*0.0.0.0"') do set IP=%%a

echo.
echo ------------------------------------------------------------------------
echo  [+] Alamat IP Server Laptop Anda : http://%IP%:8000
echo  [+] Pastikan HP Anda terhubung ke Wi-Fi yang sama dengan laptop ini!
echo  [+] Masukkan alamat IP di atas pada aplikasi SemaiKu di HP Anda.
echo ------------------------------------------------------------------------
echo.
echo Menjalankan FastAPI & Uvicorn...
echo.

cd /d "%~dp0"
python -m uvicorn api_server:app --host 0.0.0.0 --port 8000

pause
