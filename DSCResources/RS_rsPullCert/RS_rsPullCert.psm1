Function Get-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name,
    [string]$PublicKey
  )
  return @{
    'Name' = $Name
    'PublicKey' = $PublicKey
  }
}

Function Get-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name,
    [string]$PublicKey
  )
  return @{
    'Name' = $Name
    'PublicKey' = $PublicKey
  }
}

Function Test-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name,
    [string]$PublicKey
  )
  $PullServerAddress = (Get-Content $(Join-Path ([Environment]::GetEnvironmentVariable('defaultPath','Machine')) 'secrets.json') -Raw | ConvertFrom-Json).PullServerAddress
  $RootCertID = (Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $("CN=$PullServerAddress")}).Thumbprint
  $SystemCertID = (Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $("CN=$PullServerAddress")}).Thumbprint

  if($RootCertID -eq $SystemCertID) {
    # Checking pull server public certificate file if $PublicKey parameter was specified
    if ($PublicKey) {
      if (Test-Path $PublicKey) {
        $PublicKeyObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $PublicKeyObj.Import($PublicKey)
        if ($PublicKeyObj.Thumbprint -ne $SystemCertID) {
          Write-Verbose "Pull certificate public key does not match the installed cert"
          return $false
        }
      }
      else {
        Write-Verbose "Pull certificate public key is not found: $PublicKey"
        return $false
      }
    }
    return $true
  }
  else {
    return $false
  }
}

Function Set-TargetResource {
  param (
    [parameter(Mandatory = $true)][string]$Name,
    [string]$PublicKey
  )
  $PullServerAddress = (Get-Content $(Join-Path ([Environment]::GetEnvironmentVariable('defaultPath','Machine')) 'secrets.json') -Raw | ConvertFrom-Json).PullServerAddress
  $SystemCertID = (Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $("CN=$PullServerAddress")}).Thumbprint
  $RootCertID = (Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $("CN=$PullServerAddress")}).Thumbprint
  $yesterday = (Get-Date).AddDays(-1) | Get-Date -Format MM/dd/yyyy
  
  #check missing certificates
  if ($SystemCertID -ne $null) {
    if ($SystemCertID -ne $RootCertID) {
      CopyPullCertToRootStore -PullServerAddress $PullServerAddress
    }
  }
  else {
    Write-Verbose "Creating Pull server certificate..."
    Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object -FilterScript {$_.Subject -eq $("CN=$PullServerAddress")} | Remove-Item
    & makecert.exe -b $yesterday -r -pe -n $("CN=$PullServerAddress"), -ss my, -sr localmachine, -len 2048
    CopyPullCertToRootStore -PullServerAddress $PullServerAddress
  }

  # Export Pulic key to a .cer file for use in local pull DSC configuration
  if ($PublicKey) {
    if (Test-Path $PublicKey) {
      $PublicKeyObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
      $PublicKeyObj.Import($PublicKey)
      if ($PublicKeyObj.Thumbprint -ne $SystemCertID) {
        Write-Verbose "Re-exporting Pull server certificate public key to: $PublicKey"
        (Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -eq "CN=$PullServerAddress") | Export-Certificate -Type CERT -FilePath $PublicKey -Force
      }
    }
    else {
      Write-Verbose "Pull certificate public key file not found - exporting it to $PublicKey"
      (Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -eq "CN=$PullServerAddress") | Export-Certificate -Type CERT -FilePath $PublicKey -Force
    }
  }
}

Function CopyPullCertToRootStore {
  param (
    [parameter(Mandatory = $true)][string]$PullServerAddress
  )
  Write-Verbose "Copying Pull server certificate to root store"
  Get-ChildItem -Path Cert:\LocalMachine\Root\ | Where-Object -FilterScript {$_.Subject -eq $("CN=$PullServerAddress")} | Remove-Item
  $store = Get-Item Cert:\LocalMachine\Root
  $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadWrite')
  $store.Add( $(New-Object System.Security.Cryptography.X509Certificates.X509Certificate -ArgumentList @(,(Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -eq "CN=$PullServerAddress").RawData)) )
  $store.Close()
}

Export-ModuleMember -Function *-TargetResource
