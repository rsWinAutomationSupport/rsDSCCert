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
  
  # Check if a self-signed Pull server certificate already exists - create it if it is not present
  $PullCertThumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')}).Thumbprint
  if ($PullCertThumbprint -eq $null)
  {
    $EndDate = (Get-Date).AddYears(25) | Get-Date -Format MM/dd/yyyy
    New-SelfSignedCertificateEx -Subject $('CN=', $d.PullServerAddress -join '') `
                                -NotAfter $EndDate `
                                -StoreLocation LocalMachine `
                                -StoreName My `
                                -Exportable `
                                -KeyLength 2048
    $PullCertThumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')}).Thumbprint
  }
  
  # Replace pull certificate in root store if it does not match one in system personal store
  $RootPullCertThumbprint = (Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $('CN=', $d.PullServerAddress -join '')}).Thumbprint
  
  if ( -not ($PullCertThumbprint -eq $RootPullCertThumbprint))
  {
    if ($RootPullCertThumbprint -ne $null)
    {
      Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.thumbprint -eq $RootPullCertThumbprint} | Remove-Item
    }
  
    # Copy the Pull server certificate to the root store
    $SourceStoreScope = 'LocalMachine'
    $SourceStorename = 'My'
    
    $SourceStore = New-Object  -TypeName System.Security.Cryptography.X509Certificates.X509Store  -ArgumentList $SourceStorename, $SourceStoreScope
    $SourceStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $PullCertObj = $SourceStore.Certificates | 
                    Where-Object -FilterScript {
                        $_.Thumbprint -eq $PullCertThumbprint
                    }
    
    $DestStoreScope = 'LocalMachine'
    $DestStoreName = 'root'
    
    $DestStore = New-Object  -TypeName System.Security.Cryptography.X509Certificates.X509Store  -ArgumentList $DestStoreName, $DestStoreScope
    $DestStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $DestStore.Add($PullCertObj)
    
    $SourceStore.Close()
    $DestStore.Close()
  }
}

Export-ModuleMember -Function *-TargetResource
