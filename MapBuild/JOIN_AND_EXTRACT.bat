@echo off
rem Joins the parts back into one archive and extracts it here (Windows 10/11, no extra software).
cd /d "%~dp0"
echo Joining 11 parts...
copy /b SquishyDuels_MapBuild.tar.xz.001 + SquishyDuels_MapBuild.tar.xz.002 + SquishyDuels_MapBuild.tar.xz.003 + SquishyDuels_MapBuild.tar.xz.004 + SquishyDuels_MapBuild.tar.xz.005 + SquishyDuels_MapBuild.tar.xz.006 + SquishyDuels_MapBuild.tar.xz.007 + SquishyDuels_MapBuild.tar.xz.008 + SquishyDuels_MapBuild.tar.xz.009 + SquishyDuels_MapBuild.tar.xz.010 + SquishyDuels_MapBuild.tar.xz.011 SquishyDuels_MapBuild.tar.xz >nul
echo Extracting...
tar -xf SquishyDuels_MapBuild.tar.xz
echo Done: the SquishyDuels_MapBuild folder is next to this file.
pause
