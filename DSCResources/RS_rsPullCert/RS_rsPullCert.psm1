Function Get-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name
  )
  return @{
    'Name' = $Name
  }
}

Function Test-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name
  )
  if((((Get-ChildItem Cert:\LocalMachine\My\, Cert:\LocalMachine\Root\)  | ? subject -EQ ("CN=$env:COMPUTERNAME")).thumbprint).count -le 1) {
    return $false
  }
  else {
    if((Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $env:COMPUTERNAME -join '')}).Thumbprint -eq (Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $env:COMPUTERNAME -join '')}).Thumbprint) {
      return $true
    }
    else {
      return $false
    }
  }
}

Function Set-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name
  )
  $yesterday = (Get-Date).AddDays(-1) | Get-Date -Format MM/dd/yyyy
  Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $env:COMPUTERNAME -join '')} | Remove-Item
  & makecert.exe -b $yesterday -r -pe -n $('CN=', $env:COMPUTERNAME -join ''), -ss my, -sr localmachine, -len 2048
  Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $env:COMPUTERNAME -join '')} | Remove-Item
  $store = Get-Item Cert:\LocalMachine\Root
  $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadWrite')
  $store.Add( $(New-Object System.Security.Cryptography.X509Certificates.X509Certificate -ArgumentList @(,(Get-ChildItem Cert:\LocalMachine\My | ? Subject -eq "CN=$env:COMPUTERNAME").RawData)) )
  $store.Close()
}

Export-ModuleMember -Function *-TargetResource
