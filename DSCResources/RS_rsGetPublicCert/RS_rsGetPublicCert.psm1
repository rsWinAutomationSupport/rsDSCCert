Function Get-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name
  )
  $nodeinfo = Get-Content ([Environment]::GetEnvironmentVariable('nodeInfoPath','Machine').ToString()) -Raw | ConvertFrom-Json
  $uri = "https://$($nodeinfo.PullServerIP):$($nodeinfo.PullServerPort)"
  $webRequest = [Net.WebRequest]::Create($uri)
  try { $webRequest.GetResponse() } catch {}
  $cert = $webRequest.ServicePoint.Certificate
  return @{
    'Name' = $Name
  }
}

Function Test-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name
  )
  $nodeinfo = Get-Content ([Environment]::GetEnvironmentVariable('nodeInfoPath','Machine').ToString()) -Raw | ConvertFrom-Json
  $uri = "https://$($nodeinfo.PullServerIP):$($nodeinfo.PullServerPort)"
  $webRequest = [Net.WebRequest]::Create($uri)
  try { $webRequest.GetResponse() } catch {}
  $cert = $webRequest.ServicePoint.Certificate
  if((Get-ChildItem Cert:\LocalMachine\Root).Thumbprint -contains ($cert.GetCertHashString())) {
    return $true
  }
  else {
    return $false
  }

}

Function Set-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name
  )
  $nodeinfo = Get-Content ([Environment]::GetEnvironmentVariable('nodeInfoPath','Machine').ToString()) -Raw | ConvertFrom-Json
  $uri = "https://$($nodeinfo.PullServerIP):$($nodeinfo.PullServerPort)"
  $webRequest = [Net.WebRequest]::Create($uri)
  try { $webRequest.GetResponse() } catch {}
  $cert = $webRequest.ServicePoint.Certificate
  Write-Verbose "Adding PullServer Root Certificate to Cert:\LocalMachine\Root"
  Get-ChildItem -Path "Cert:\LocalMachine\Root\" | ? Subject -EQ $("CN=", $nodeinfo.PullServerName -join '') | Remove-Item
  $store = Get-Item Cert:\LocalMachine\Root
  $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadWrite')
  $store.Add($cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $store.Close()
}

Export-ModuleMember -Function *-TargetResource
