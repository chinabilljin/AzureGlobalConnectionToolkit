  $moduleList = Get-Module -ListAvailable

  $AzureRmStorage = $moduleList | Where-Object { $_.Name -eq "AzureRm.Storage" }
  $AzureRmCompute = $moduleList | Where-Object { $_.Name -eq "AzureRm.Compute" }
  $AzureRMNetwork = $moduleList | Where-Object { $_.Name -eq "AzureRm.Network" }
  $AzureRMProfile = $moduleList | Where-Object { $_.Name -eq "AzureRm.Profile" }

  function Check-AzurePSModule
  {
    Param( [PSObject] $module )

    if ( $module -eq $null )
    { Throw "AzureRm PowerShell Module does not successfully install on PowerShell Environment. Please Install before execute this script." }

    if ( ($module.Version.Major -ge 2) -or (($module.Version.Major -eq 1) -and ( $module.Version.Minor -ge 7 ) ) )
    { break }
    else
    { Throw "This script requires AzureRm PowerShell version higher than 1.7.0. Please install the latest Azure Powershell before execute this script." }
    
  }

  Check-AzurePSModule -module $AzureRmStorage
  Check-AzurePSModule -module $AzureRmCompute
  Check-AzurePSModule -module $AzureRMNetwork
  Check-AzurePSModule -module $AzureRMProfile
