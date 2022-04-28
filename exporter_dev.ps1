###################### CHANGE ME !!!!!!!!!!!!!
$InstanceName = 'DCVW-UNFDBA-S1'
$uname = 'MCH\cavaz'
###################### CHANGE ME !!!!!!!!!!!!!


# config. shell
$ErrorActionPreference = 'Stop' # stops execution if command fails
Import-Module -Name dbatools

##### 0. Ligação à Instância Primária
[DbaInstance[]]$myInstances = $InstanceName
$myAdminCredential = Get-Credential -Message 'SQL Server Administrator Primary' -UserName $uname # opens a dialog that asks for password to access SQL Server Instances. NOTE: MCH\cavaz
$servers = Connect-DbaInstance -SqlInstance $myInstances -SqlCredential $myAdminCredential



##### 1. Encontrar ConfigurationFile.ini e guardar cópia
# $installdir = (Invoke-DbaQuery -SqlInstance $servers -Query "
# declare @rc int, @dir nvarchar(4000) 

# exec @rc = master.dbo.xp_instance_regread
#       N'HKEY_LOCAL_MACHINE',
#       N'Software\Microsoft\MSSQLServer\Setup',
#       N'SQLPath', 
#       @dir output, 'no_output'
# select @dir AS installdirectory
# ").installdirectory

# $remoteinstalldir="`\`\$InstanceName`\" + $installdir.replace(':','$');
# $fname = $InstanceName.replace('`\','_'); 

# $compatibilityLevel = (Invoke-DbaQuery -SqlInstance $servers -Query "SELECT max(compatibility_level) FROM sys.databases").Column1

# $remotelogdir = "$remoteinstalldir\..\..\$compatibilityLevel\Setup Bootstrap\Log"

# # sacar path do ConfigurationFile.ini do ficheiro de log da última instalação no servidor
# $configFileLine = (((( Get-Content -Path "$remotelogdir\Summary.txt" ) | Select-String "CONFIGURATIONFILE").Line)[0])

# # se summary.txt nao tiver path para configurationfile.ini, procurar por orderm cronologica inversa nas diretorias de logs por um configurationfile.ini
# if (" " -eq $configFileLine) {
#     $logdirlist = ((Get-ChildItem $remotelogdir -Attributes Directory).Name) | Sort -Descending
#     foreach ($dirname in $logdirlist) {
#         if ((Get-ChildItem ("$remotelogdir\$dirname")).Name -contains "ConfigurationFile.ini") {
#             $remoteconfigdir = "$remotelogdir\$dirname\ConfigurationFile.ini"
#             break
#         }
#     }
# } else {
#     $configfilepath=$configFileLine.Substring((($configFileLine.LastIndexOf(':'))-1),($configFileLine.Length)-(($configFileLine.LastIndexOf(':'))-1))
#     $remoteconfigdir="`\`\$InstanceName`\" + $configfilepath.replace(':','$');
# }

# $configfile = Get-Content -Path $remoteconfigdir

# # selecionar algumas configurações para guardar em variáveis
# $propertiesToSave = "SQLCOLLATION","AGTSVCACCOUNT","ISSVCSTARTUPTYPE","ISSVCACCOUNT", "SQLSVCACCOUNT","SQLSVCSTARTUPTYPE","SQLSYSADMINACCOUNTS","INSTANCEDIR","INSTALLSQLDATADIR","SQLUSERDBDIR","SQLUSERDBLOGDIR","SQLTEMPDBDIR"

# $foundProperties  = (($configfile | Select-String $propertiesToSave) -split '"')

# # O seguinte bloco determina se a ConfigurationFile.ini é a correta ao verificar a existência de algumas configurações essenciais, como a diretoria to TempDB. Se não encontrar,
# # itera todas as COnfigurationFile.ini por ordem cronológica inversa até achar uma que tenha toda a informação necessária à instalação
# if (($foundProperties.Count/3) -ne ($propertiesToSave.Count)) {
    
#     $logdirlist = ((Get-ChildItem $remotelogdir -Attributes Directory).Name) | Sort -Descending
#     foreach ($dirname in $logdirlist) {
#         if ((Get-ChildItem ("$remotelogdir\$dirname")).Name -contains "ConfigurationFile.ini") {
#             $configfile = Get-Content -Path "$remotelogdir\$dirname\ConfigurationFile.ini"
#             $foundProperties  = (($configfile | Select-String $propertiesToSave) -split '"')
#             if (($foundProperties.Count/3) -eq ($propertiesToSave.Count)) {
#                 break
#             }
#         }
#     }

# }


# # import data from configuration file

# $InstallProperties = @();

# foreach ($property in $propertiesToSave) {
#     $values = (($configfile | Select-String $property) -split '"')
#     if ($values.Count -gt 3) {
#         $finalvalues=""
#         for ($i = 1; $i -lt $values.Count; $i=$i+2) {
#             if ($i -eq ($values.Count - 2)) {
#                 $finalvalues += $values[($i)]
#                 break
#             }
#             $finalvalues += $values[$i] + ", "
#         }
#         $finalvalues += $values[($i+2)]
#     }else {
#         $finalvalues = $values[1]
#     }
    
#     $InstallProperties += @{$property = $finalvalues}
    
# }

# ##### 2. Importar objetos

# # 2.1. allow dedicated admin connection temporarily to export objects
 Invoke-DbaQuery -SqlInstance $servers -Query " sp_configure 'remote admin connections', 1;
 RECONFIGURE;"

# # 2.2. LOGINS (pode demorar)
# Export-DbaUser -SqlInstance $servers -FilePath "$PSScriptRoot\logins\$fname.sql"

# 2.3. JOBS

$options = New-DbaScriptingOption
$options.ScriptSchema = $true
$options.IncludeDatabaseContext = $true
$options.IncludeHeaders = $true
$options.ScriptBatchTerminator = $true
$options.AnsiFile = $true

$date = Get-Date -Format "yyyyMMdd"
$ct = 0

# export user jobs
$jobs = Get-DbaAgentJob -SqlInstance $servers

if (-not (Test-Path "$PSScriptRoot\jobs\$fname")) {
    New-Item -ItemType Directory -Force -Path "$PSScriptRoot\jobs\$fname"
}

foreach ($job in $jobs) {
    $jname = $job.Name
    $jname = $jname.replace("/","_") 
    $job | Export-DbaScript -FilePath "$PSScriptRoot\jobs\$fname\$ct`_$jname`_$date.sql" -ScriptingOptionsObject $options
    $ct += 1
}
echo "Saved Jobs to $PSScriptRoot\jobs\$fname\"

# 2.4. LINKED SERVERS

# Export-DbaLinkedServer -SqlInstance $servers -FilePath "$PSScriptRoot\linkedServers\$fname.sql"
# echo "Saved Linked Servers to $PSScriptRoot\linkedServers\$fname.sql"

# # 2.5. PROXIES
# Get-DbaAgentProxy -SqlInstance $servers | Export-DbaScript -FilePath "$PSScriptRoot\proxies\$fname.sql"
# echo "Saved Proxies to $PSScriptRoot\proxies\$fname.sql"

# # 2.6. CREDENCIAIS
# Export-DbaCredential -SqlInstance $servers -FilePath "$PSScriptRoot\credentials\$fname.sql"
# echo "Saved Credentials to $PSScriptRoot\credentials\$fname.sql"

# # 2.7. E-MAIL
# Get-DbaDbMail -SqlInstance $servers | Export-DbaScript -FilePath "$PSScriptRoot\email\$fname.sql"
# echo "Saved Email to $PSScriptRoot\email\$fname.sql"

# # 2.8. Configuration file
# Copy-Item -Path "$remotelogdir\$dirname\ConfigurationFile.ini" -Destination "$PSScriptRoot\configFiles\$fname`_ConfigurationFile.ini"
# echo "Saved Config File to $PSScriptRoot\configFiles\$fname`_ConfigurationFile.ini"

# 2.9. disallow dac again
Invoke-DbaQuery -SqlInstance $servers -Query " sp_configure 'remote admin connections', 0;
RECONFIGURE;"

# 2.10. Paths dos datagiles

# $dbList = (Get-DbaDatabase -SqlInstance $servers -ExcludeSystem).Name

# $AsResults = @();
# foreach ($db in $dblist) {
#     $AsResult = @();
#     $dfile = Get-DbaDbFile -SqlInstance $servers -Database $db
#     $pDataFile = ($dfile | Where-Object FileGroupName -eq "PRIMARY").PhysicalName
#     $logDataFile = ($dfile | Where-Object TypeDescription -eq "LOG").PhysicalName
#     $DataFile = ($dfile | Where-Object FileGroupName -eq "DATA").PhysicalName

#     $AsResult = New-Object PSObject -Property @{ 
#         dbName = $db;
#         primary = $pDataFile;
#         log = $logDataFile;
#         data = $DataFile
#     }
#     $AsResults += $AsResult;
# }

# $AsResults | Select-Object "dbName", "primary", "log", "data" | ConvertTo-Json | Out-File "$PSScriptRoot\dataFiles\$fname`_dfiles.json"

# echo "Saved Data File Paths to $PSScriptRoot\dataFiles\$fname`_dfiles.json"

# ##### 3. Informação Always - On

# $agobj = Get-DbaAvailabilityGroup -SqlInstance $servers

# if ($null -eq $agobj){
#     $agstatus = "NoAg"
# }else {
#     # save AG info to disk
#     $agname = $agobj.AvailabilityGroupListeners.Name
#     $agip = $agobj.AvailabilityGroupListeners.AvailabilityGroupListenerIPAddresses.IPAddress
#     $agport = $agobj.AvailabilityGroupListeners.PortNumber
#     $agsnetmask = $agobj.AvailabilityGroupListeners.AvailabilityGroupListenerIPAddresses.SubnetMask
#     $agsnetip = $agobj.AvailabilityGroupListeners.AvailabilityGroupListenerIPAddresses.SubnetIP

#     $AsResult = New-Object PSObject -Property @{ 
#         AGName = $agname
#         AGIP = $agip
#         AGPort = $agport
#         AGSubnetMask = $agsnetmask
#         AGSubnetIP = $agsnetip
#     }
#     $AsResult | Select-Object "AGName", "AGIP", "AGPort", "AGSubnetMask", "AGSubnetIP" | ConvertTo-Json | Out-File "$PSScriptRoot\AGinfo\$fname`_AGinfo.json"

#     #GARANTIR QUE É PRIMARIA
#     if ($InstanceName -ne ($agobj.AvailabilityReplicas | Where-Object role -eq 'Primary').Name ) {
#         Write-Output "You're not on the primary replica. Switch to the $(($agobj.AvailabilityReplicas | Where-Object role -eq 'Primary').Name) and try again."
#         exit
#     }else {
#         # Remove-DbaAgDatabase -SqlInstance $servers -AvailabilityGroup $agname -Confirm:$false
#     }

# }
    

#### 4. detach each database one by one

# foreach ($db in $dbList) {
#     Write-Output "Detaching $db..."
#     Dismount-DbaDatabase -SqlInstance $servers -Database $db
# }

echo $done

Disconnect-DbaInstance