# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$InstanceName = 'DCVW-SBXDBS-T2'#'DCVW-SBXDBS-T1' # 'DCVW-PHWDBS-D1' #primaria
#$InstanceName = 'DCVW-PHWDBS-D1'
#$InstanceName = 'DCVW-MDEDBA-S1'

$uname = 'MCH\cavaz'
$ErrorActionPreference = 'Stop' # stops execution if command fails
Import-Module -Name dbatools


# 0. Ligação à Instância Primária
[DbaInstance[]]$myInstances = $InstanceName
$myAdminCredential = Get-Credential -Message 'SQL Server Administrator Primary' -UserName $uname # opens a dialog that asks for password to access SQL Server Instances. NOTE: MCH\cavaz
$servers = Connect-DbaInstance -SqlInstance $myInstances -SqlCredential $myAdminCredential

$fname = $InstanceName.replace('`\','_'); 

# allow dedicated admin connection temporarily to export objects
Invoke-DbaQuery -SqlInstance $servers -Query " sp_configure 'remote admin connections', 1;
# RECONFIGURE;"

# 1. Import AG info
$agobj = Get-Content -Raw -Path "$PSScriptRoot\AGinfo\$fname`_AGinfo.json" | ConvertFrom-Json
$agname = $agobj.AGName
$agip = $agobj.AGIP
$agport = $agobj.AGPort
$agsnetmask = $agobj.AGSubnetMask
$agsnetip = $agobj.AGSubnetIP

# 2. JOBS

# 2.1 .DBA maintenance

$listJobs = (Get-ChildItem "$PSScriptRoot\jobs\$fname" -Filter *.sql)

foreach($jobPath in $listJobs.FullName){
    # se for o Job que desliga outros Jobs não necessários na réplica, passa um argumento com o nome do AG, cas contrário, coloca só o job
    Invoke-DbaQuery -SqlInstance $servers -Database 'msdb' -File $jobPath
    }

# 2.2 pre-existing jobs

$listJobs = (Get-ChildItem "$PSScriptRoot\jobs_DBA" -Filter *.sql)

foreach($jobPath in $listJobs.FullName){
# se for o Job que desliga outros Jobs não necessários na réplica, passa um argumento com o nome do AG, cas contrário, coloca só o job
    if (($jobPath -split '\\')[-1] -eq "DBA - Activate_Deactivate SQL Server Jobs.sql") {
        $ActDeactScript = (Get-Content $jobPath) | Out-String
        Invoke-DbaQuery -SqlInstance $servers -Database 'msdb' -Query ($ActDeactScript -replace "AGNAMEGOESHERE",$agname)
        }else {
        Invoke-DbaQuery -SqlInstance $servers -Database 'msdb' -File $jobPath
    }
}


# # linked server
Invoke-DbaQuery -SqlInstance $servers -File "$PSScriptRoot\linkedServers\$fname.sql"

# # agent proxies
Invoke-DbaQuery -SqlInstance $servers -File "$PSScriptRoot\proxies\$fname.sql"

# # credentials
Invoke-DbaQuery -SqlInstance $servers -File "$PSScriptRoot\credentials\$fname.sql"

# # email (TESTAR)
Invoke-DbaQuery -SqlInstance $servers -File "$PSScriptRoot\email\$fname.sql"

# Logins
Invoke-DbaQuery -SqlInstance $servers -File "$PSScriptRoot\logins\$fname.sql"

# disallow dac again
Invoke-DbaQuery -SqlInstance $servers -Query " sp_configure 'remote admin connections', 0;
# RECONFIGURE;"

#IMPORT LOCATION DATAFILES
# "$PSScriptRoot\dataFiles\$fname`_dfilesPath.json"

$dfiles = Get-Content -Raw -Path "$PSScriptRoot\dataFiles\$fname'_dfiles.json" | ConvertFrom-Json

foreach ($dfile in $dfiles) {
    $fileStructure = New-Object System.Collections.Specialized.StringCollection
    $fileStructure.Add("E:\archive\example.mdf")
    $filestructure.Add("E:\archive\example.ldf")
    $filestructure.Add("E:\archive\example.ndf")
    Mount-DbaDatabase -SqlInstance sql2016 -Database example -FileStructure $fileStructure
}

foreach ($db in $dblist) {
    $AsResult = @();
    $dfile = Get-DbaDbFile -SqlInstance $servers -Database $db
    $pDataFile = ($dfile | Where-Object FileGroupName -eq "PRIMARY").PhysicalName
    $logDataFile = ($dfile | Where-Object TypeDescription -eq "LOG").PhysicalName
    $DataFile = ($dfile | Where-Object FileGroupName -eq "DATA").PhysicalName

    $AsResult = New-Object PSObject -Property @{ 
        dbName = $db;
        primary = $pDataFile;
        log = $logDataFile;
        data = $DataFile
    }

    $AsResults += $AsResult;
}

$AsResults | Select-Object "dbName", "primary", "log", "data" | ConvertTo-Json | Out-File "$PSScriptRoot\dataFiles\$fname`_dfilesPath.json"

#check if AO is configured and remove it from AG if so

$agobj = Get-DbaAvailabilityGroup -SqlInstance $servers

if ($null -eq $agobj){
    $agstatus = "NoAg"
}else {
    # save AG info to disk
    $agname = $agobj.AvailabilityGroupListeners.Name
    $agip = $agobj.AvailabilityGroupListeners.AvailabilityGroupListenerIPAddresses.IPAddress
    $agport = $agobj.AvailabilityGroupListeners.PortNumber
    $agsnetmask = $agobj.AvailabilityGroupListeners.AvailabilityGroupListenerIPAddresses.SubnetMask
    $agsnetip = $agobj.AvailabilityGroupListeners.AvailabilityGroupListenerIPAddresses.SubnetIP

    $AsResult = New-Object PSObject -Property @{ 
        AGName = $agname
        AGIP = $agip
        AGPort = $agport
        AGSubnetMask = $agsnetmask
        AGSubnetIP = $agsnetip
    }
    $AsResult | Select-Object "AGName", "AGIP", "AGPort", "AGSubnetMask", "AGSubnetIP" | ConvertTo-Json | Out-File "$PSScriptRoot\AGinfo\$fname`_AGinfo.json"

    #GARANTIR QUE É PRIMARIA
    if ($InstanceName -ne ($agobj.AvailabilityReplicas | Where-Object role -eq 'Primary').Name ) {
        Write-Output "You're not on the primary replica. Switch to the $(($agobj.AvailabilityReplicas | Where-Object role -eq 'Primary').Name) and try again."
        exit
    }else {
        Remove-DbaAgDatabase -SqlInstance $servers -AvailabilityGroup $agname -Confirm:$false
    }

}
    

# detach each database one by one

foreach ($db in $dbList) {
    Write-Output "Detaching $db..."
    Dismount-DbaDatabase -SqlInstance $servers -Database $db
}

# $instanceName = "DCVW-PHWDBS-D1"
# $fname = $InstanceName.replace('`\','_'); 
# $myAdminCredential = Get-Credential -Message 'SQL Server Administrator Primary' -UserName $uname # opens a dialog that asks for password to access SQL Server Instances. NOTE: MCH\cavaz
# Export-DbaUser -SqlInstance $instanceName -SqlCredential $myAdminCredential -FilePath "$PSScriptRoot\jobs\$fname`_logins.sql" -Append

# 2. Create and grant sysadmin server permissions por logins in ADlogins
# foreach($Login in $ADlogins)
#     {
#         New-DbaLogin -SqlInstance $servers -Login $Login -DefaultDatabase master
#         Add-DbaServerRoleMember -SqlInstance $servers -ServerRole sysadmin -Login $Login -Confirm:$false
#     }

# # 3 Create NewRelic and SCOM users on all non-system DBs and grant server permissions
# foreach($Login in $LoginsToPropagate)
#     {
#         Invoke-DbaQuery -SqlInstance $servers -Query "GRANT CONNECT SQL TO[$Login];
#         GRANT VIEW SERVER STATE TO[$Login];
#         GRANT VIEW ANY DEFINITION TO[$Login];"
#         # 3.2 Criar user em todas as BDs fora das de sistema
#         New-DbaDbUser -SqlInstance $servers -ExcludeDatabase 'master','msdb','tempdb','model','rdsadmin','distribution' -Login $Login
#         #$DBnames = (Get-DbaDatabase -SqlInstance $server -ExcludeSystem).Names
#     }

# 4. Criar JOBS
# $listJobs = (Get-ChildItem "$PSScriptRoot\jobs" -Filter *.sql)


# foreach($jobPath in $listJobs.FullName)
#     {
#         # se for o Job que desliga outros Jobs não necessários na réplica, passa um argumento com o nome do AG, cas contrário, coloca só o job
#          if (($jobPath -split '\\')[-1] -eq "DBA - Activate_Deactivate SQL Server Jobs.sql") {
#             $ActDeactScript = (Get-Content $jobPath) | Out-String
#             Invoke-DbaQuery -SqlInstance $servers -Database 'msdb' -Query ($ActDeactScript -replace "AGNAMEGOESHERE",$AGName)
#          }else {
#             Invoke-DbaQuery -SqlInstance $servers -Database 'msdb' -File $jobPath
#          }
#     }


Disconnect-DbaInstance