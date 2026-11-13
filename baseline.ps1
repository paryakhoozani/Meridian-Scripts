# baseline.ps1 -- READ-ONLY snapshot of a Windows host, plus a diff mode. Run as Administrator.
#   powershell -ExecutionPolicy Bypass -File baseline.ps1 snap [label]
#   powershell -ExecutionPolicy Bypass -File baseline.ps1 diff <dirA> <dirB>
# In diff output: "=>" means only in the newer snapshot (new), "<=" means gone.
param([string]$Mode, [string]$A, [string]$B)
$ErrorActionPreference = 'SilentlyContinue'
function Save($out, $name, $data) { $data | Out-String -Width 300 | Set-Content -Path (Join-Path $out $name) -Encoding UTF8 }

if ($Mode -eq 'snap') {
  $label = if ($A) { $A } else { 'snap' }
  $out = Join-Path $env:ProgramData ("baseline\{0}-{1}-{2}" -f $env:COMPUTERNAME, $label, (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Force -Path $out | Out-Null

  Save $out 'os.txt' (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version)
  Save $out 'listening.txt' (Get-NetTCPConnection -State Listen | Sort-Object LocalPort, LocalAddress | Select-Object LocalAddress, LocalPort, @{n='Process';e={(Get-Process -Id $_.OwningProcess).Name}})
  Save $out 'listening_udp.txt' (Get-NetUDPEndpoint | Sort-Object LocalPort | Select-Object LocalAddress, LocalPort)
  Save $out 'processes.txt' (Get-CimInstance Win32_Process | Select-Object Name, ProcessId, ParentProcessId, CommandLine)
  Save $out 'local_users.txt' (Get-LocalUser | Sort-Object Name | Select-Object Name, Enabled, PasswordLastSet)
  Save $out 'local_admins.txt' (net localgroup administrators)
  if (Get-Command Get-ADGroupMember -ErrorAction SilentlyContinue) {
    Save $out 'ad_privileged.txt' (@('Domain Admins','Enterprise Admins','Schema Admins','Administrators') | ForEach-Object { "== $_"; Get-ADGroupMember $_ | Sort-Object SamAccountName | Select-Object SamAccountName, objectClass })
    Save $out 'ad_users.txt' (Get-ADUser -Filter * -Properties PasswordLastSet | Sort-Object SamAccountName | Select-Object SamAccountName, Enabled, PasswordLastSet)
  }
  Save $out 'sched_tasks.txt' (Get-ScheduledTask | ForEach-Object { [pscustomobject]@{ Path=$_.TaskPath; Name=$_.TaskName; User=$_.Principal.UserId; Action=(($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; ') } } | Sort-Object Path, Name)
  Save $out 'services.txt' (Get-CimInstance Win32_Service | Sort-Object Name | Select-Object Name, StartMode, StartName, PathName)
  Save $out 'run_keys.txt' (@('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce') | ForEach-Object { "== $_"; Get-ItemProperty $_ | Format-List })
  Save $out 'startup_folders.txt' (Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup", "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" -Force | Select-Object FullName)
  Save $out 'wmi_persistence.txt' (@('__EventFilter','__EventConsumer','__FilterToConsumerBinding') | ForEach-Object { "== $_"; Get-CimInstance -Namespace root\subscription -ClassName $_ | Out-String })
  Save $out 'shares.txt' (Get-SmbShare | Select-Object Name, Path, Description)
  Save $out 'smb_config.txt' (Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol)
  Save $out 'firewall.txt' ((Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction), (Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow | Sort-Object DisplayName | Select-Object DisplayName))
  Save $out 'recent_files.txt' (Get-ChildItem C:\Users\Public, C:\Windows\Temp, C:\ProgramData -Recurse -Depth 3 -File -Force | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-2) -and $_.FullName -notlike '*\baseline\*' } | Select-Object -First 500 FullName, LastWriteTime)
  "snapshot saved: $out"
}
elseif ($Mode -eq 'diff' -and (Test-Path $A) -and (Test-Path $B)) {
  Get-ChildItem $A -Filter *.txt | Where-Object { $_.Name -notin 'processes.txt','recent_files.txt','listening_udp.txt' } | ForEach-Object {
    $d = Compare-Object (Get-Content $_.FullName) (Get-Content (Join-Path $B $_.Name))
    if ($d) { "=== $($_.Name)"; $d | ForEach-Object { "{0} {1}" -f $_.SideIndicator, $_.InputObject } }
  }
}
else { "usage: baseline.ps1 snap [label] | baseline.ps1 diff <dirA> <dirB>" }
