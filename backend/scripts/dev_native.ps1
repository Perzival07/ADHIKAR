<#
.SYNOPSIS
  Run the ADHIKAR backend natively on this machine: Qdrant/Redis/Postgres in Docker (loopback only) and the
  Python services from .venv, so they can talk to a model server on 127.0.0.1 (Ollama) that containers cannot reach.

.EXAMPLE
  scripts/dev_native.ps1 up                 # infra + 7 services, real LLM (models.ollama.yaml) + bge-m3 on CPU
  scripts/dev_native.ps1 up -Mock           # same stack on the mock LLM + hash embedder
  scripts/dev_native.ps1 ingest             # (re)build the vector index with the current embedder
  scripts/dev_native.ps1 status             # /ready of every service
  scripts/dev_native.ps1 logs llm-gateway   # tail a service log
  scripts/dev_native.ps1 down

  Options: -Models <file> (llm-gateway routing), -EmbedProvider sentence_transformers|ollama|hash,
           -EmbedModelPath <folder> (bge-m3 by default), -OllamaUrl http://127.0.0.1:11434, -NoAuth
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][ValidateSet('up', 'down', 'status', 'ingest', 'logs')][string]$Cmd = 'status',
  [Parameter(Position = 1)][string]$Arg = '',
  [string]$Models = 'services/llm-gateway/models.ollama.yaml',
  [ValidateSet('sentence_transformers', 'ollama', 'hash')][string]$EmbedProvider = 'sentence_transformers',
  [string]$EmbedModelPath = 'D:\models\bge-m3',
  [string]$EmbedOllamaModel = 'bge-m3',
  [string]$OllamaUrl = 'http://127.0.0.1:11434',
  [switch]$Mock,
  [switch]$NoAuth
)
$ErrorActionPreference = 'Stop'
$Backend = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Py = Join-Path $Backend '.venv\Scripts\python.exe'
$Logs = Join-Path $Backend '.logs'
$PidFile = Join-Path $Logs 'pids.json'
$Docs = Join-Path $Backend 'data\scheme_docs'
$PgUrl = 'postgresql+asyncpg://adhikar:adhikar-dev-only@127.0.0.1:5432/auth'
if ($Mock) { $Models = 'services/llm-gateway/models.yaml'; $EmbedProvider = 'hash' }
$ModelsAbs = if ([IO.Path]::IsPathRooted($Models)) { $Models } else { Join-Path $Backend $Models }

$Common = @{ PYTHONUNBUFFERED = '1' }
$Services = [ordered]@{
  'llm-gateway' = @{ port = 8001; app = 'llm_gateway.main:app_factory'; env = @{
      LLMGW_MODELS_FILE = $ModelsAbs; LLMGW_OLLAMA_BASE_URL = $OllamaUrl; LLMGW_CONCURRENCY = '1'; LLMGW_READ_TIMEOUT = '180' } }
  'embedding-service' = @{ port = 8002; app = 'embedding_service.main:app_factory'; env = @{
      EMBED_PROVIDER = $EmbedProvider; EMBED_MODEL_PATH = $EmbedModelPath; EMBED_DEVICE = 'cpu';
      EMBED_OLLAMA_BASE_URL = $OllamaUrl; EMBED_OLLAMA_MODEL = $EmbedOllamaModel; HF_HUB_OFFLINE = '1'; TRANSFORMERS_OFFLINE = '1' } }
  'ingestion-service' = @{ port = 8003; app = 'ingestion_service.main:app_factory'; env = @{
      INGEST_QDRANT_URL = 'http://127.0.0.1:6333'; INGEST_EMBEDDING_URL = 'http://127.0.0.1:8002'; INGEST_DOCS_DIR = $Docs;
      INGEST_STATE_DIR = (Join-Path $Backend 'services\ingestion-service\.state'); INGEST_REQUEST_TIMEOUT = '600' } }
  'retrieval-service' = @{ port = 8004; app = 'retrieval_service.main:app_factory'; env = @{
      RETRIEVAL_QDRANT_URL = 'http://127.0.0.1:6333'; RETRIEVAL_EMBEDDING_URL = 'http://127.0.0.1:8002' } }
  'eligibility-service' = @{ port = 8005; app = 'eligibility_service.main:app_factory'; env = @{ ELIG_DOCS_DIR = $Docs } }
  'auth-service' = @{ port = 8006; app = 'auth_service.main:app_factory'; env = @{
      AUTH_ENV = 'development'; AUTH_DATABASE_URL = $PgUrl; AUTH_REDIS_URL = 'redis://127.0.0.1:6379/1';
      AUTH_EMAIL_BACKEND = 'console'; AUTH_SEED_DEMO_USERS = 'true'; AUTH_CORS_ORIGINS = '*' } }
  'recommendation-service' = @{ port = 8000; app = 'recommendation_service.main:app_factory'; env = @{
      RECO_ELIGIBILITY_URL = 'http://127.0.0.1:8005'; RECO_RETRIEVAL_URL = 'http://127.0.0.1:8004';
      RECO_LLM_GATEWAY_URL = 'http://127.0.0.1:8001'; RECO_REDIS_URL = 'redis://127.0.0.1:6379/0';
      RECO_AUTH_MODE = 'optional'; RECO_AUTH_JWKS_URL = 'http://127.0.0.1:8006/.well-known/jwks.json';
      RECO_CORS_ORIGINS = '*'; RECO_LLM_TIMEOUT = '150'; RECO_REQUEST_DEADLINE = '180'; RECO_ADMIN_TOKEN = 'dev-admin-token' } }
}
if ($NoAuth) { $Services.Remove('auth-service'); $Services['recommendation-service'].env.RECO_AUTH_MODE = 'off' }
$Services['ingestion-service'].env.INGEST_CACHE_CLEAR_URL = 'http://127.0.0.1:8000/v1/admin/cache/clear'
$Services['ingestion-service'].env.INGEST_CACHE_CLEAR_TOKEN = 'dev-admin-token'

function Invoke-WithEnv([hashtable]$EnvMap, [scriptblock]$Body) {
  $saved = @{}
  foreach ($k in $EnvMap.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); Set-Item -Path "env:$k" -Value $EnvMap[$k] }
  try { & $Body }
  finally {
    foreach ($k in $EnvMap.Keys) {
      if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item -Path "env:$k" -Value $saved[$k] }
    }
  }
}

function Get-Ready([int]$Port) {
  try { $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/ready" -TimeoutSec 5 -UseBasicParsing; return @{ ok = $true; body = $r.Content } }
  catch { $b = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }; return @{ ok = $false; body = "$b" } }
}

function Start-Infra {
  Write-Host '== infra (docker, loopback only)'
  docker compose -f docker-compose.yml -f docker-compose.native.yml up -d --wait qdrant redis postgres
  if ($LASTEXITCODE -ne 0) { throw 'docker compose failed (is Docker Desktop running?)' }
}

function Show-Status {
  foreach ($name in $Services.Keys) {
    $r = Get-Ready $Services[$name].port
    $flag = if ($r.ok) { 'READY' } else { 'DOWN ' }
    $body = ($r.body -replace '\s+', ' ')
    if ($body.Length -gt 140) { $body = $body.Substring(0, 140) }
    Write-Host ("{0} {1,-24} :{2}  {3}" -f $flag, $name, $Services[$name].port, $body)
  }
}

function Stop-Services {
  if (Test-Path $PidFile) {
    $pids = Get-Content $PidFile | ConvertFrom-Json
    foreach ($prop in $pids.PSObject.Properties) {
      $proc = Get-Process -Id $prop.Value -ErrorAction SilentlyContinue
      if ($proc) { Stop-Process -Id $prop.Value -Force; Write-Host "stopped $($prop.Name) (pid $($prop.Value))" }
    }
    Remove-Item $PidFile -Force
  }
}

function Start-Services {
  if (-not (Test-Path $Py)) { throw "missing $Py - create the venv first (README: Backend install)" }
  New-Item -ItemType Directory -Force $Logs | Out-Null
  if (Test-Path $PidFile) { Stop-Services }
  if (-not $NoAuth) {
    Write-Host '== auth-service migrate'
    Invoke-WithEnv ($Common + $Services['auth-service'].env) { & $Py -m auth_service migrate }
  }
  $pids = @{}
  foreach ($name in $Services.Keys) {
    $s = $Services[$name]
    $uvArgs = @('-m', 'uvicorn', '--factory', $s.app, '--host', '127.0.0.1', '--port', "$($s.port)", '--no-access-log')
    $p = Invoke-WithEnv ($Common + $s.env) {
      Start-Process -FilePath $Py -ArgumentList $uvArgs -WorkingDirectory $Backend -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $Logs "$name.out.log") -RedirectStandardError (Join-Path $Logs "$name.log")
    }
    $pids[$name] = $p.Id
    Write-Host ("started {0,-24} pid {1,-6} :{2}" -f $name, $p.Id, $s.port)
  }
  $pids | ConvertTo-Json | Set-Content $PidFile
  Write-Host '== waiting for /ready (the embedding model takes ~30 s to load the first time)'
  $deadline = (Get-Date).AddSeconds(180)
  do {
    Start-Sleep 3
    $pending = @($Services.Keys | Where-Object { -not (Get-Ready $Services[$_].port).ok })
  } while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline)
  Show-Status
  if ($pending.Count -gt 0) { Write-Warning "not ready: $($pending -join ', ') - see .logs/<service>.log" }
}

switch ($Cmd) {
  'up'     { Set-Location $Backend; Start-Infra; Start-Services }
  'down'   { Set-Location $Backend; Stop-Services; docker compose -f docker-compose.yml -f docker-compose.native.yml stop qdrant redis postgres | Out-Null; Write-Host 'infra stopped (volumes kept)' }
  'status' { Show-Status }
  'ingest' { Set-Location $Backend; Invoke-WithEnv ($Common + $Services['ingestion-service'].env) { & $Py -W ignore -m ingestion_service ingest } }
  'logs'   { if (-not $Arg) { throw 'usage: dev_native.ps1 logs <service>' }; Get-Content (Join-Path $Logs "$Arg.log") -Tail 60 -Wait }
}
