$ErrorActionPreference = "Stop"
$model = "qwen2.5:3b"
Write-Host "MARVIN AI Studio - Local Engine Setup" -ForegroundColor Cyan
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
  Write-Host "Ollama is not installed. Install it from https://ollama.com/download, then reopen PowerShell." -ForegroundColor Yellow
  exit 1
}
try {
  Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 3 | Out-Null
} catch {
  Write-Host "Starting the local Ollama server..." -ForegroundColor Yellow
  Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
  Start-Sleep -Seconds 5
}
Write-Host "Downloading model $model (this may take a while)..." -ForegroundColor Cyan
ollama pull $model
if ($LASTEXITCODE -ne 0) { throw "Model download failed. Check your internet connection and try again." }
try {
  $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 10
  $found = $tags.models | Where-Object { $_.name -like "qwen2.5:3b*" }
  if (-not $found) { throw "Model was not found after download." }
  Write-Host "Engine ready. Open ai-studio locally and click Check connection." -ForegroundColor Green
} catch {
  Write-Host "Model downloaded, but the local API did not respond. Open Ollama and retry." -ForegroundColor Yellow
  throw
}
