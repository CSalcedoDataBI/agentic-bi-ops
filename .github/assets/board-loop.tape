# board-loop.tape — VHS script for the SECOND README GIF (issue #210).
#
# Renders .github/assets/board-loop.gif: agentic-board in use — ask what's
# pending, start an issue, open a review-gated PR, merge to Done. Driven by
# board-loop.ps1 (simulated typing; deterministic).
#
# Regenerate (Windows):  vhs .github/assets/board-loop.tape   (from the repo root)
#   needs: winget install charmbracelet.vhs · ffmpeg · ttyd.exe on PATH

Output .github/assets/board-loop.gif

Set Shell "pwsh"
Set FontSize 22
Set Width 1240
Set Height 860
Set Padding 30
Set WindowBar Colorful
Set TypingSpeed 6ms

Hide
Type "[Console]::OutputEncoding=[Text.Encoding]::UTF8"
Enter
Type "Set-Location $HOME\Repos\agentic-bi-ops\.github\assets"
Enter
Type "Clear-Host"
Enter
Show

Type ".\board-loop.ps1"
Enter
Sleep 14s
