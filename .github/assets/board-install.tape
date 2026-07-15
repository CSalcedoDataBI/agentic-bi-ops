# board-install.tape — VHS script for the README hero GIF (issue #210).
#
# Renders .github/assets/board-install.gif: install agentic-board, the banner
# splash, and the /board menu. Driven by board-demo.ps1 (simulated typing).
#
# Regenerate (Windows, from the repo root):
#   vhs .github/assets/board-install.tape
#   needs: winget install charmbracelet.vhs · ffmpeg · ttyd.exe on PATH

Output .github/assets/board-install.gif

Set Shell "pwsh"
Set FontSize 24
Set Width 1300
Set Height 880
Set Padding 34
Set WindowBar Colorful
Set TypingSpeed 8ms

Hide
Type "[Console]::OutputEncoding=[Text.Encoding]::UTF8"
Enter
Type "Set-Location $HOME\Repos\agentic-bi-ops\.github\assets"
Enter
Type "Clear-Host"
Enter
Show

Type ".\board-demo.ps1"
Enter
Sleep 13s
