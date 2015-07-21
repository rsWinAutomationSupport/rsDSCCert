function Get-NodeInfo {
$nodeinfo = Get-Content ([Environment]::GetEnvironmentVariable('nodeInfoPath','Machine').ToString()) -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
if(!($nodeinfo)){ $nodeinfo = Get-Content 'C:\Windows\Temp\nodeinfo.json' -Raw | ConvertFrom-Json }
return $nodeinfo
}




function Update-HOSTS {
param(
$oldName,
$oldIP
)


$nodeinfo = Get-NodeInfo

if(!($oldName)){ $oldName = $nodeinfo.PullServerName }
if(!($oldIP)){ $oldIP = $nodeinfo.PullServerIP }

#Select content of HOSTS file and replace anything matching the old PullServerName or IP   
$hostfile = (Get-Content -Path 'C:\Windows\system32\drivers\etc\hosts') -replace "$oldName","$nodeinfo.PullServerName" -replace "$oldIP","$nodeinfo.PullServerIP"    #.where({$_ -notmatch $($nodeinfo.PullServerIP) -AND $_ -notmatch $($nodeinfo.PullServerName)})

Set-Content -Path 'C:\Windows\System32\Drivers\etc\hosts' -Value $hostfile -Force

}




function Create-LCMJob {

$nodeinfo = Get-NodeInfo

$argument = @"
    Configuration LCM
    {
        Node $env:COMPUTERNAME
        {
                LocalConfigurationManager
                    {
                        AllowModuleOverwrite = 'True'
                        ConfigurationID = '$($nodeinfo.uuid)'
                        CertificateID = (Get-ChildItem Cert:\LocalMachine\My | ? Subject -EQ "CN=$($env:COMPUTERNAME)_enc").Thumbprint
                        ConfigurationModeFrequencyMins = 30
                        ConfigurationMode = 'ApplyAndAutoCorrect'
                        RebootNodeIfNeeded = 'True'
                        RefreshMode = 'Pull'
                        RefreshFrequencyMins = 30
                        DownloadManagerName = 'WebDownloadManager'
                        DownloadManagerCustomData = (@{ServerUrl = 'https://$($nodeinfo.PullServerName):$($nodeinfo.PullServerPort)/PSDSCPullServer.svc'; AllowUnsecureConnection = 'false'})
                    }
               
        }
    }
    Stop-DscConfiguration -Force -ErrorAction SilentlyContinue
    LCM -OutputPath 'C:\Windows\Temp' -Verbose
    Set-DscLocalConfigurationManager -Path 'C:\Windows\Temp' -Verbose
    Start-DscConfiguration -UseExisting -Force
"@


$timer = (Get-Date).AddMinutes(2)

$action = New-ScheduledTaskAction -Execute "$PSHOME\powershell.exe" -Argument $argument
$trigger = New-ScheduledTaskTrigger -At $timer -Once

if(Get-ScheduledTask -TaskName 'Update-LCM' -ErrorAction SilentlyContinue){ Get-ScheduledTask -TaskName 'Update-LCM' | Unregister-ScheduledTask -Confirm:$false }

Register-ScheduledTask -TaskName 'Update-LCM' -User 'System' -Trigger $trigger -Action $action

}




Function Get-TargetResource {
  param (
    [parameter(Mandatory)]
    [ValidateSet("Present","Absent")]
    [string] $Ensure,
    [string] $PullServerAddress,
    [int] $PullServerPort
  )
  
  $nodeinfo = Get-NodeInfo
  
  if(!($PullServerAddress)){ $PullServerAddress = $nodeinfo.PullServerAddress }
  if(!($PullServerPort)){ $PullServerAddress = $nodeinfo.PullServerPort }
  
  
  return @{
    'Ensure' = $Ensure
    'PullServerAddress' = $PullServerAddress
    'PullServerPort' = $PullServerPort
    
  }
}




Function Test-TargetResource {
  param (
    [parameter(Mandatory)]
    [ValidateSet("Present","Absent")]
    [string] $Ensure,
    [string] $PullServerAddress,
    [int] $PullServerPort
  )
  
  if($Ensure -eq 'Present'){
  
          #First check if PullServer Address or Port have changed compared to nodeinfo.json locally
          $nodeinfo = Get-NodeInfo
  
          if($PullServerAddress){
                if($PullServerAddress -ne $nodeinfo.PullServerAddress) {return $false}
          }

          if($PullServerPort){
                if($PullServerPort -ne $nodeinfo.PullServerPort) {return $false}
          }

          #If PullServer Address or Port have not changed, validate that the current PullServer public cert is installed locally
          $uri = "https://$($nodeinfo.PullServerName):$($nodeinfo.PullServerPort)"
          $webRequest = [Net.WebRequest]::Create($uri)
          
          #catch returns false in case connection times out, this will reset HOSTS entry in Set function
          try { $webRequest.GetResponse() } catch { return $false }
          $cert = $webRequest.ServicePoint.Certificate
          if((Get-ChildItem Cert:\LocalMachine\Root).Thumbprint -contains ($cert.GetCertHashString())) {
            return $true
          }
          else {
            return $false
          }
    }

    else { Write-Verbose -Message "Ensure set to Absent, skipping tests, no action to take" }
}

Function Set-TargetResource {
  param (
    [parameter(Mandatory)]
    [ValidateSet("Present","Absent")]
    [string] $Ensure,
    [string] $PullServerAddress,
    [int] $PullServerPort
  )
  
        
            #Update PullServer Address and Port in $nodeinfo if changed
                        
            $nodeinfo = Get-NodeInfo
          
            if($PullServerPort){
                $nodeinfo.PullServerPort = $PullServerPort
            }
          

            if($PullServerAddress){
                $nodeinfo.PullServerAddress = $PullServerAddress
                
                if($nodeinfo.PullServerAddress -match '[a-zA-Z]'){ $nodeinfo.PullServerName = $nodeinfo.PullServerAddress }
                         
                #If PullServerAddress contains only an IP, set the PullServerIP variable to the IP entered
                #Attempt to get the PullServer's hostname from the certificate attached to the endpoint.
                #Ensure PullServer endpoint cert is installed locally.
                #ensure HOSTS file contains correct PullServerName and IP
                else{ 
                    
                    $oldName = $nodeinfo.PullServerName
                    $oldIP = $nodeinfo.PullServerIP
                    $nodeinfo.PullServerIP = $nodeinfo.PullServerAddress

                    $uri = "https://$($nodeinfo.PullServerIP):$($nodeinfo.PullServerPort)"
    
                    $webRequest = [Net.WebRequest]::Create($uri)
    
                    try {$webRequest.GetResponse()}catch {}
    
                    $nodeinfo.PullServerName = $webRequest.ServicePoint.Certificate.Subject -replace '^CN\=','' -replace ',.*$',''
            
                    $cert = $webRequest.ServicePoint.Certificate
                    Write-Verbose "Adding PullServer Root Certificate to Cert:\LocalMachine\Root"
                    Get-ChildItem -Path "Cert:\LocalMachine\Root\" | ? Subject -EQ $("CN=", $nodeinfo.PullServerName -join '') | Remove-Item
                    $store = Get-Item Cert:\LocalMachine\Root
                    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadWrite')
                    $store.Add($cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
                    $store.Close()

                    Update-HOSTS -oldName $oldName -oldIP $oldIP
                }
            }
          

            
            

            #Ensure LCM is configured correctly. Will create a Scheduled Task to set the LCM 2 minutes after current DSC run finishes
            Create-LCMJob
    
}

Export-ModuleMember -Function *-TargetResource
