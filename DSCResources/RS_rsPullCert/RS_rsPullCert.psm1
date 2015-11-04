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
  $d = Get-Content $(Join-Path ([Environment]::GetEnvironmentVariable('defaultPath','Machine')) 'secrets.json') -Raw | ConvertFrom-Json
  if((Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')}).Thumbprint -eq (Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')}).Thumbprint) {
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
  # Import extra functions for use in the resource
  Get-Item (Join-Path -Path $PSScriptRoot -ChildPath 'helper_scripts\*.ps1') | 
    ForEach-Object {
        Write-Verbose ("Importing " -f $_.FullName)
        . $_.FullName
    }

  $d = Get-Content $(Join-Path ([Environment]::GetEnvironmentVariable('defaultPath','Machine')) 'secrets.json') -Raw | ConvertFrom-Json
  
  Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')} | Remove-Item

  $EndDate = (Get-Date).AddYears(25) | Get-Date -Format MM/dd/yyyy
  New-SelfSignedCertificateEx -Subject $('CN=', $d.PullServerAddress -join '') `
                              -NotAfter $EndDate `
                              -StoreLocation LocalMachine `
                              -StoreName My `
                              -Exportable `
                              -KeyLength 2048

  Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')} | Remove-Item
  $store = Get-Item Cert:\LocalMachine\Root
  $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadWrite')
  $store.Add( $(New-Object System.Security.Cryptography.X509Certificates.X509Certificate -ArgumentList @(,(Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -eq "CN=$d.PullServerAddress").RawData)) )
  $store.Close()
}

Export-ModuleMember -Function *-TargetResource
