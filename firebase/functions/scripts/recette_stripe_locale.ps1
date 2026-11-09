# Recette Stripe LOCALE (mode test) de l'espace commercant ProxiPlay.
#
# A lancer dans VOTRE fenetre PowerShell :
#   powershell -ExecutionPolicy Bypass -File .\scripts\recette_stripe_locale.ps1
#
# Securite de la cle :
#   - saisie masquee (Read-Host -AsSecureString) : jamais affichee, jamais
#     dans l'historique des commandes (seule la ligne ci-dessus y figure) ;
#   - gardee uniquement dans l'environnement de CE processus et de ses
#     processus enfants (Stripe CLI, serveur local) ; aucun fichier, aucun setx ;
#   - seules les cles de TEST (sk_test_ / rk_test_) sont acceptees ;
#   - effacee a l'arret (Entree, ou Ctrl+C puis fermeture de la fenetre).
#
# Pre-requis : emulateurs Auth + Firestore lances (projet demo-proxiplay-stripe),
# Stripe CLI installee, site servi sur http://localhost:5500.

param(
  [int]$AuthPort = 9099,
  [int]$FirestorePort = 8080,
  [int]$BillingPort = 35001,
  [string]$SiteOrigin = 'http://localhost:5500',
  [string]$LogDir = (Join-Path $env:TEMP 'proxiplay-recette-stripe'),
  # Taux de TVA de la sandbox (txr_...) : recette dans les conditions LIVE
  # (STRIPE_TAX_MODE=tax_rate). Sans lui : aucune taxe ajoutee.
  [string]$TaxRateId = ''
)

$ErrorActionPreference = 'Continue'
$functionsDir = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
# Un journal horodate par lancement : jamais de troncature d'un fichier
# qu'un autre lecteur (ou une recette precedente) tiendrait ouvert.
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$serverLog = Join-Path $LogDir "serveur-facturation-$runId.log"
$listenLog = Join-Path $LogDir "stripe-listen-$runId.log"

# Ecriture en mode partage (lecture/ecriture), tolerante aux lecteurs
# concurrents ; une ligne impossible a ecrire n'arrete jamais la recette.
$appendBlock = {
  param($path, $text)
  try {
    $stream = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
      $bytes = [Text.Encoding]::UTF8.GetBytes($text + [Environment]::NewLine)
      $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
  } catch { }
}

function Stop-Recette {
  param([string]$Message)
  if ($Message) { Write-Host $Message -ForegroundColor Red }
  foreach ($name in 'STRIPE_SECRET_KEY', 'STRIPE_API_KEY', 'STRIPE_WEBHOOK_SECRET') {
    Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
  }
}

# Masque toute valeur sensible avant ecriture dans les journaux.
$maskBlock = {
  param($line)
  ($line | Out-String).TrimEnd() -replace '(sk|rk)_(test|live)_[A-Za-z0-9]+', '$1_$2_***' -replace 'whsec_[A-Za-z0-9]+', 'whsec_***'
}

# --- 0. Pre-requis ---------------------------------------------------------
if (-not (Get-Command stripe -ErrorAction SilentlyContinue)) {
  Stop-Recette 'Stripe CLI introuvable (commande "stripe"). Installez-la puis relancez.'; return
}
foreach ($port in $AuthPort, $FirestorePort) {
  try { Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 3 | Out-Null }
  catch { Stop-Recette "Emulateur absent sur le port $port : lancez les emulateurs Auth et Firestore."; return }
}

# --- 1. Saisie masquee de la cle de TEST -------------------------------------
$secure = Read-Host -AsSecureString 'Cle secrete Stripe de TEST (sk_test_...)'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr); $secure.Dispose() }
if ($plain -notmatch '^(sk|rk)_test_[A-Za-z0-9]+$') {
  Remove-Variable plain; Stop-Recette 'Cle refusee : seule une cle Stripe de TEST est acceptee.'; return
}
$env:STRIPE_SECRET_KEY = $plain   # serveur local de facturation
$env:STRIPE_API_KEY = $plain      # Stripe CLI (evite la cle sur la ligne de commande)
Remove-Variable plain

# Parametres de la recette locale uniquement.
if ($TaxRateId) {
  if ($TaxRateId -notmatch '^txr_[A-Za-z0-9]+$') { Stop-Recette 'TaxRateId invalide (txr_...).'; return }
  $env:STRIPE_TAX_MODE = 'tax_rate'
  $env:STRIPE_TAX_RATE_ID = $TaxRateId
} else {
  $env:STRIPE_TAX_MODE = 'none'
}
$env:GCLOUD_PROJECT = 'demo-proxiplay-stripe'
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:$FirestorePort"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:$AuthPort"
$env:LOCAL_BILLING_PORT = "$BillingPort"
$env:LOCAL_SITE_ORIGIN = $SiteOrigin
Remove-Item Env:STRIPE_LIVE_MODE_ENABLED -ErrorAction SilentlyContinue

$jobs = @()
try {
  Push-Location $functionsDir

  # --- 2. Verification des prix chez Stripe (lecture seule) ------------------
  Write-Host "`nVerification des prix Stripe..." -ForegroundColor Cyan
  node scripts/check_stripe_config.js --env=.env.local
  if ($LASTEXITCODE -ne 0) { throw 'Verification des prix en echec (voir ci-dessus).' }

  # --- 3. Secret de signature des webhooks de la Stripe CLI ------------------
  $whsec = ((stripe listen --print-secret 2>$null) | Out-String).Trim()
  if ($whsec -notmatch '^whsec_') { throw 'Impossible d''obtenir le secret webhook de la Stripe CLI.' }
  $env:STRIPE_WEBHOOK_SECRET = $whsec
  Remove-Variable whsec

  # --- 4. Reception des webhooks + serveur local ----------------------------
  $events = 'checkout.session.completed,checkout.session.expired,customer.subscription.created,' +
    'customer.subscription.updated,customer.subscription.deleted,customer.subscription.paused,' +
    'customer.subscription.resumed,invoice.paid,invoice.payment_failed,charge.refunded,charge.dispute.created'
  $jobs += Start-Job -Name 'stripe-listen' -ArgumentList $BillingPort, $events, $listenLog, $maskBlock.ToString(), $appendBlock.ToString() -ScriptBlock {
    param($port, $events, $log, $mask, $append)
    $maskFn = [scriptblock]::Create($mask)
    $appendFn = [scriptblock]::Create($append)
    stripe listen --events $events --forward-to "http://127.0.0.1:$port/stripeWebhook" 2>&1 |
      ForEach-Object { & $appendFn $log (& $maskFn $_) }
  }
  $jobs += Start-Job -Name 'serveur-facturation' -ArgumentList $functionsDir, $serverLog, $maskBlock.ToString(), $appendBlock.ToString() -ScriptBlock {
    param($dir, $log, $mask, $append)
    $maskFn = [scriptblock]::Create($mask)
    $appendFn = [scriptblock]::Create($append)
    Set-Location $dir
    node scripts/local_billing_server.js 2>&1 |
      ForEach-Object { & $appendFn $log (& $maskFn $_) }
  }

  Start-Sleep -Seconds 6
  Write-Host "`nRecette prete." -ForegroundColor Green
  Write-Host "  Site     : $SiteOrigin/espace-commercant/?emulator=1&authPort=$AuthPort&functionsPort=$BillingPort"
  Write-Host "  Journaux : $serverLog"
  Write-Host "             $listenLog"
  Write-Host "  Carte de test : 4242 4242 4242 4242, date future, CVC 123"
  Read-Host "`nAppuyez sur Entree pour ARRETER la recette et effacer la cle de la session"
}
catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
  foreach ($job in $jobs) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
  # Processus enfants eventuellement restants (Stripe CLI, serveur local).
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -eq 'stripe.exe' -and $_.CommandLine -match 'listen') -or
      ($_.Name -eq 'node.exe' -and $_.CommandLine -match 'local_billing_server\.js') } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Pop-Location -ErrorAction SilentlyContinue
  Stop-Recette
  Write-Host 'Recette arretee : cle et secret webhook effaces de la session.' -ForegroundColor Yellow
}
