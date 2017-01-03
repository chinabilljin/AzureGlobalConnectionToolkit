function Check-AzureRmMigrationPSRequirement
{
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

    if ( !(($module.Version.Major -ge 2) -or (($module.Version.Major -eq 1) -and ( $module.Version.Minor -ge 7 ))) )
    { Throw "This script requires AzureRm PowerShell version higher than 1.7.0. Please install the latest Azure Powershell before execute this script." }
    
  }

  Check-AzurePSModule -module $AzureRmStorage
  Check-AzurePSModule -module $AzureRmCompute
  Check-AzurePSModule -module $AzureRMNetwork
  Check-AzurePSModule -module $AzureRMProfile

}

Function MigrationTelemetry 
{
    Param(
          [Parameter(Mandatory=$true)]
          [PSObject] $srcContext,

          [Parameter(Mandatory=$false)]
          [PSObject] $destContext,

          [Parameter(Mandatory=$false)]
          [PSObject] $vmProfile,

          [Parameter(Mandatory=$false)]
          [ValidateSet("UserInput", "PreValidation","Preparation", "VhdCopy", "VMBuild", "PostValidate")]
          [String] $phaseName = "",

          [Parameter(Mandatory=$false)]
          [ValidateSet("Succeed", "Failed", "Started")]
          [String] $phaseStatus = "Started",

          [Switch] $completed

        )
    $path = [environment]::getfolderpath("mydocuments") + "\WindowsPowerShell\Modules\AzureGlobalConnectionToolkit\CICDTool"

    #record timespan for each phase
    $dateTime = Get-Date
    
    $duration = If ($timeSpanList.Count -eq 0) {
        0
    } else {
        for($i=$timeSpanList.Count-1;$i -ge 0;$i-- ) {
            if($timeSpanList[$i].PhaseName -ne $phaseName) {
                $lastPhaseDateTime = $timeSpanList[$i].DateTime
                break
            }
        }
        ($dateTime - $lastPhaseDateTime).TotalSeconds.ToString("F1")
    }

    $timeSpan = New-Object -TypeName PSObject 
    $timeSpan | Add-Member -MemberType NoteProperty -Name PhaseName -Value $phaseName 
    $timeSpan | Add-Member -MemberType NoteProperty -Name PhaseStatus -Value $phaseStatus
    $timeSpan | Add-Member -MemberType NoteProperty -Name DateTime -Value $dateTime 
    $timeSpan | Add-Member -MemberType NoteProperty -Name TimeSpan -Value $duration 

    $Script:timeSpanList += $timeSpan

    #just record the start time when phase name was not provided, so no table upgrade
    if($phaseName -eq "") {return}

    $dic = @{}
    $dic.Add("Completed",$completed.IsPresent)
    $dic.Add("SrcContext",(ConvertTo-Json $srcContext))
    $dic.Add("DestContext",(ConvertTo-Json $destContext))
    $dic.Add("VmProfile",(ConvertTo-Json $vmProfile))
    $dic.Add("SourceEnvironment",$srcContext.Environment.Name)
    $dic.Add("SourceSubscriptionId",$srcContext.Subscription.SubscriptionId)
    $dic.Add("SourceTenantId",$srcContext.Tenant.TenantId)
    $dic.Add("DestinationEnvironment",$destContext.Environment.Name)
    $dic.Add("DestinationSubscriptionId",$destContext.Subscription.SubscriptionId)
    $dic.Add("DestinationTenantId",$destContext.Tenant.TenantId)
    $dic.Add("VmSize",$vmProfile.HardwareProfile.VmSize)
    $dic.Add("VmLocation",$vmProfile.Location)
    $dic.Add("VmOsType",$vmProfile.StorageProfile.OsDisk.OsType)
    $dic.Add("VmNumberOfDataDisk",$vmProfile.StorageProfile.DataDisks.Count)
    $vmProfile.StorageInfos | Where-Object {$_.IsOSDisk -eq $true} | %{$dic.Add("VmOsDiskSzie",$_.BlobActualBytes)}
    $vmProfile.StorageInfos | Where-Object {$_.IsOSDisk -eq $false} | %{$dic.Add(("VmDataDisk"+$_.Lun+"Size"),$_.BlobActualBytes)}
    $Global:timeSpanList | Where-Object {$_.phaseStatus -ne "Started"} | %{
      $dic.Add(($_.phaseName+"TimeSpan"),$_.TimeSpan);
      $dic.Add(($_.phaseName+"Status"),$_.PhaseStatus);
    }

    Start-Job -ScriptBlock {
        Get-ChildItem ($args[0] + "\lib") | % { Add-Type -Path $_.FullName }
        $telemetry = New-Object Microsoft.Azure.CAT.Migration.Storage.MigrationTelemetry
        $telemetry.AddOrUpdateEntity($args[1],$args[2],$args[3])
    } -ArgumentList $path, $srcContext.Account, $Script:JobId, $dic | Receive-Job -Wait -AutoRemoveJob

}

function Start-AzureRmVMMigrationValidate
{
  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] 
    $vm,

    [Parameter(Mandatory=$False)]
    [AllowNull()]
    [Object[]] 
    $RenameInfos,

    [Parameter(Mandatory=$True)]
    [String] $targetLocation,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $SrcContext,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $DestContext  

  )

  ##Parameter Type Check
  if ( $vm -ne $null)
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "-vm : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-DestContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext"
    }
  }
  
  if ($RenameInfos.Count -ne 0)
  {
    ForEach( $RenameInfo in $RenameInfos )
    {
      if ( $RenameInfo.GetType().FullName -notmatch "ResourceProfile" )
      {
        Throw "-RenameInfos : parameter type is invalid. Please enter the right parameter type: ResourceProfile"
      }
    }
  }

  ####Write Progress####

  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Validating" -percentComplete 0
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Started" -percentComplete 0


  Class ResourceProfile
  {
    [String] $ResourceType
    [String] $SourceResourceGroup
    [String] $DestinationResourceGroup
    [String] $SourceName
    [String] $DestinationName
    [String] $DnsName
  }

  ####Get VM Components####
  if($RenameInfos.Count -ne 0)
  {
    $vmResources = $RenameInfos
  }
  else
  {
    Function Add-ResourceList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [String] $resourceId
      )
    
      $resource = New-Object ResourceProfile
      $resource.DestinationName = $resourceId.Split("/")[8]
      $resource.ResourceType = $resourceId.Split("/")[7]
      $resource.DestinationResourceGroup = $resourceId.Split("/")[4]
   
      $resourceCheck = $vmResources | Where-Object { ($_.SourceName -eq $resource.SourceName) -and ($_.ResourceType -eq $resource.ResourceType) -and ($_.SourceResourceGroup -eq $resource.SourceResourceGroup) }
   
      if ( $resourceCheck -eq $null )
      {
        if ($resource.ResourceType -eq "publicIPAddresses")
        {
          $pip = Get-AzureRmPublicIpAddress -Name $resource.SourceName -ResourceGroupName $resource.SourceResourceGroup
          $resource.DnsName = $pip.DnsSettings.DomainNameLabel
        }
        $Script:vmResources += $resource
      }
    }

    Function Add-StorageList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [String] $storName   
      )

      $storCheck = $vmResources | Where-Object { ($_.SourceName -eq $storName) -and ($_.ResourceType -eq "storageAccounts" ) }

      if ( $storCheck -eq $null )
      {
        $targetStor = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storName }
      
        $resource = New-Object ResourceProfile
        $resource.DestinationName = $targetStor.StorageAccountName
        $resource.ResourceType = "storageAccounts"
        $resource.DestinationResourceGroup = $targetStor.ResourceGroupName

        $Script:vmResources += $resource
      }
    }  
    
    Set-AzureRmContext -Context $SrcContext | Out-Null

    #VM
    $Script:vmResources = @()

    Add-ResourceList -resourceId $vm.Id

    #AS
    if ($vm.AvailabilitySetReference -ne $null)
    {
      Add-ResourceList -resourceId $vm.AvailabilitySetReference.Id
    }
   

    #NIC
    if ($vm.NetworkInterfaceIDs -ne $null)
    { 
      foreach ( $nicId in $vm.NetworkInterfaceIDs )
      {
        Add-ResourceList -resourceId $nicId
            
        $nic = Get-AzureRmNetworkInterface | Where-Object { $_.Id -eq $nicId }
     
        foreach ( $ipConfig in $nic.IpConfigurations )
        {
          #LB
          foreach( $lbp in $ipConfig.LoadBalancerBackendAddressPools)
          {   
            Add-ResourceList -resourceId $lbp.Id
            
            #PIP-LB
            $lb = Get-AzureRmLoadBalancer -Name $lbp.Id.Split("/")[8] -ResourceGroupName $lbp.Id.Split("/")[4]
                                  
            foreach ( $fip in $lb.FrontendIpConfigurations )
            {
               Add-ResourceList -resourceId $fip.PublicIpAddress.Id
            }  
          }

          #VN
         
          Add-ResourceList -resourceId $ipConfig.Subnet.Id

          #NSG-VN
          $vn = Get-AzureRmVirtualNetwork -Name $ipConfig.Subnet.Id.Split("/")[8] -ResourceGroupName $ipConfig.Subnet.Id.Split("/")[4]
           
          foreach ( $subnet in $vn.Subnets)
          {
            if ( $subnet.NetworkSecurityGroup -ne $null)
            {
              Add-ResourceList -resourceId $subnet.NetworkSecurityGroup.Id                
            }
          }
         

          #PIP-nic
          if ($ipConfig.PublicIpAddress -ne $null)
          {
            Add-ResourceList -resourceId $ipConfig.PublicIpAddress.Id
          }
        }
     
        #NSG-nic
        if ($nic.NetworkSecurityGroup -ne $null)
        {
          Add-ResourceList -resourceId $nic.NetworkSecurityGroup.Id
        }

      }
    }

    #OSDisk
    $osuri = $vm.StorageProfile.OsDisk.Vhd.Uri
    if ( $osuri -match "https" ) 
    {
      $osstorname = $osuri.Substring(8, $osuri.IndexOf(".blob") - 8)
    }
    else 
    {
      $osstorname = $osuri.Substring(7, $osuri.IndexOf(".blob") - 7)
    }
    Add-StorageList -storName $osstorname


    #DataDisk
    foreach($dataDisk in $vm.StorageProfile.DataDisks)
    {
      $datauri = $dataDisk.Vhd.Uri
      if ( $datauri -match "https" ) {
      $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
      else {
        $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
      }
      Add-StorageList -storName $datastorname
    } 
  }

  ####Start Validation####


  Enum ResultType
  {
    Failed = 0
    Succeed = 1
    SucceedWithWarning = 2
  }

  Function Add-ResultList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [ResultType] $result,
      [Parameter(Mandatory=$False)]
      [String] $detail
    )
    
    $messageHeader = $null
    switch($result){
      "Failed"{
          $Script:result = "Failed"
          $messageHeader = "[Error] "
      }
      "SucceedWithWarning"{
          if($Script:result -eq "Succeed"){
              $Script:result = "SucceedWithWarning"
          }
          $messageHeader = "[Warning] "
      }
    }
    if($detail){
      $Script:resultDetailsList += $messageHeader + $detail
    }
  }

  Function Get-AzureRmVmCoreFamily
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $VmSize   
    )
    switch -regex ($VmSize) 
    { 
      "^Basic_A[0-4]$" {"Basic A Family Cores"} 
      "^Standard_A[0-7]$" {"Standard A0-A7 Family Cores"}
      "^Standard_A([89]|1[01])$" {"Standard A8-A11 Family Cores"} 
      "^Standard_D1?[1-5]_v2$" {"Standard Dv2 Family Cores "} 
      "^Standard_D1?[1-4]$" {"Standard D Family Cores"} 
      "^Standard_G[1-5]$" {"Standard G Family Cores"} 
      "^Standard_DS1?[1-4]$" {"Standard DS Family Cores"} 
      "^Standard_DS1?[1-5]_v2$" {"Standard DSv2 Family Cores"} 
      "^Standard_GS[1-5]$" {"Standard GS Family Cores"} 
      "^Standard_F([1248]|16)$" {"Standard F Family Cores"} 
      "^Standard_F([1248]|16)s$" {"Standard FS Family Cores"} 
      "^Standard_NV(6|12|24)$" {"Standard NV Family Cores"} 
      "^Standard_NC(6|12|24)$" {"Standard NC Family Cores"} 
      "^Standard_H(8m?|16m?r?)$" {"Standard H Family Cores"} 
      default {"The Core Family could not be determined."}
    }
  }

  #Define Validation Result and Message
  $Script:result = "Succeed"
  $Script:resultDetailsList = @()

  #check src permission
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Permission" -percentComplete 10

  Set-AzureRmContext -Context $SrcContext | Out-Null
  $roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $SrcContext.Account

  if(!($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner")) 
  {
    Add-ResultList -result "Failed" -detail "The current user don't have source subscription permission, because the user is not owner or coAdmin."
  }


  #check dest permission
  Set-AzureRmContext -Context $DestContext | Out-Null
  $roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $DestContext.Account

  if(!($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner")) 
  {
    Add-ResultList -result "Failed" -detail "The current user don't have source subscription permission, because the user is not owner or coAdmin."
  }


  # Core Quota Check
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Quota" -percentComplete 30
  Set-AzureRmContext -Context $DestContext | Out-Null

  $vmHardwareProfile = Get-AzureRmVmSize -Location $targetLocation | Where-Object{$_.Name -eq $vm.HardwareProfile.VmSize}
  if($vmHardwareProfile -eq $null)
  {
    Add-ResultList -result "Failed" -detail ("Target location: " + $targetLocation + " doesn't have VM type: " + $vm.HardwareProfile.VmSize)
  }
  
  $vmCoreNumber = $vmHardwareProfile.NumberOfCores

  $vmCoreFamily = Get-AzureRmVmCoreFamily -VmSize $vm.HardwareProfile.VmSize

  $vmUsage = Get-AzureRmVMUsage -Location $targetLocation
  $vmTotalCoreUsage = $vmUsage | Where-Object{$_.Name.LocalizedValue -eq "Total Regional Cores"}
  $vmFamilyCoreUsage = $vmUsage | Where-Object{$_.Name.LocalizedValue -eq $vmCoreFamily}

  $vmAvailableTotalCore = $vmTotalCoreUsage.Limit - $vmTotalCoreUsage.CurrentValue
  $vmAvailableFamilyCoreUsage = $vmFamilyCoreUsage.Limit - $vmFamilyCoreUsage.CurrentValue

  if($vmCoreNumber -gt $vmAvailableTotalCore) 
  {
    Add-ResultList -result "Failed" -detail ("The vm core quota validate failed, because destination subscription does not have enough regional quota. Current quota left: " + $vmAvailableTotalCore + ". VM required: " + $vmCoreNumber + "." )
  }


  if($vmCoreNumber -gt $vmAvailableFamilyCoreUsage) 
  {
    Add-ResultList -result "Failed" -detail ("The vm core quota validate failed, because destination subscription does not have enough " + $vmCoreFamily + " quota. Current quota left: " + $vmAvailableFamilyCoreUsage + ". VM required: " + $vmCoreNumber + "." )
  }


  #Storage Quota Check
  $storageAccountsCount = 0
  foreach ($resource in $vmResources) {
    if($resource.ResourceType -eq "storageAccounts"){
      $storageAccountsCount += 1
    }
  }
  $storageUsage = Get-AzureRmStorageUsage
  $storageAvailable = $storageUsage.Limit - $storageUsage.CurrentValue

  if($storageAccountsCount -gt $storageAvailable)
  {
    Add-ResultList -result "Failed" -detail ("The storage account quota validate failed, because destination subscription does not have enough storage account quota. Current quota left: " + $storageAvailable + ". VM required: " + $storageAccountsCount + "." )
  }


  # Storage Name Existence
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Name Availability" -percentComplete 50
  $storageAccountNames = @()
  foreach ( $resource in $vmResources)
  {
    if($resource.ResourceType -eq "storageAccounts")
    {
      $saCheck = $storageAccountNames | Where-Object { $_ -eq $resource.DestinationName }
      if ( $saCheck -eq $null )
      {
        $storageAccountNames += $resource.DestinationName
      }
    }
  }

  Set-AzureRmContext -Context $DestContext | Out-Null
  Foreach ($storage in $storageAccountNames)
  {
    $storageCheck = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storage}

    if ( $storageCheck -eq $null )
    {
      $storageAvailability = Get-AzureRmStorageAccountNameAvailability -Name $storage
      if ($storageAvailability.NameAvailable -eq $false)
      {
        Add-ResultList -result "Failed" -detail ("The storage account " + $storage + " validate failed, because " + $storageAvailability.Reason)
      }

    }
    else
    {
      Add-ResultList -result "SucceedWithWarning" -detail ("storage account name: " + $storage + " exist in the subscription")
    }
  }

  ## Check DNS Name Availability

  foreach ( $resource in $vmResources)
  {
    if($resource.ResourceType -eq "publicIPAddresses")
    {    
      if(!([string]::IsNullOrEmpty($resource.DnsName)))
      {
        Set-AzureRmContext -Context $DestContext | Out-Null  
        $dnsTestResult = Test-AzureRmDnsAvailability -DomainNameLabel $resource.DnsName -Location $targetLocation
        if($dnsTestResult -ne "True")
        {
            Add-ResultList -result "Failed" -detail ("The dns name: " + $resource.DnsName + " validate failed, because DNS name not available in target location.")
        }
      }
    }
  }

  ##Check Resource Existence
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Resource Existence" -percentComplete 70
  Set-AzureRmContext -Context $DestContext | Out-Null

  $DestResources = Get-AzureRmResource 

  foreach ( $resource in $vmResources)
  {
    $resourceCheck = $DestResources | Where-Object {$_.ResourceType -match $resource.ResourceType } | 
                                    Where-Object {$_.ResourceId.Split("/")[4] -eq $resource.DestinationResourceGroup} | 
                                    Where-Object {$_.Name -eq $resource.DestinationName}
    if ($resourceCheck -ne $null)
    {
      switch ($resource.ResourceType) 
      { 
          "virtualMachines" {$resourceResult = "Failed"} 
          "availabilitySets" {$resourceResult = "Failed"}
          "networkInterfaces" {$resourceResult = "Failed"}
          "loadBalancers" {$resourceResult = "SucceedWithWarning"}
          "publicIPAddresses" {$resourceResult = "SucceedWithWarning"}
          "virtualNetworks" {$resourceResult = "SucceedWithWarning"}
          "networkSecurityGroups" {$resourceResult = "SucceedWithWarning"}
          "storageAccounts" {$resourceResult = "SucceedWithWarning"}
      }
      Add-ResultList -result $resourceResult -detail ("The resource:" + $resource.DestinationName +  " (type: "+$resource.ResourceType+") in Resource Group: " + $resource.DestinationResourceGroup + " already exists in destination.")
    }
    


  }

  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Complete" -percentComplete 100

  $validationResult = New-Object PSObject
  $validationResult | Add-Member -MemberType NoteProperty -Name Result -Value $Script:result
  $validationResult | Add-Member -MemberType NoteProperty -Name Messages -Value $Script:resultDetailsList

  return $validationResult
}

function Start-AzureRmVMMigrationPrepare
{
  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] $vm,

    [Parameter(Mandatory=$True)]
    [String] $targetLocation,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $SrcContext,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $DestContext,  

    [Parameter(Mandatory=$false)]
    [AllowNull()]
    [Object[]]
    $RenameInfos

  )


  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "-vm : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-DestContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext"
    }
  }


  if ($RenameInfos.Count -ne 0)
  {
    ForEach( $RenameInfo in $RenameInfos )
    {
      if ( $RenameInfo.GetType().FullName -notmatch "ResourceProfile" )
      {
        Throw "`-RenameInfos : parameter type is invalid. Please enter the right parameter type: ResourceProfile"
      }
    }
  }

  ####Write Progress####

  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Preparing Migration" -percentComplete 5
  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Started" -percentComplete 0

  ####Collecting VM Information####

  Set-AzureRmContext -Context $SrcContext | Out-Null

  #Get Dependencies
  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Getting Dependencies" -percentComplete 15

  ##Handle Resource Group Dependencies: List Distinct Resource Group

  $Script:resourceGroups = @()
  $Script:storageAccounts = @()

  if ($RenameInfos.Count -eq 0)
  {
    Function Add-ResourceGroupList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [String] $rgName
      )

      $rgCheck = $resourceGroups | Where-Object { $_.ResourceGroupName -eq $rgName }

      if ( $rgCheck -eq $null )
      {
        $targetRg = Get-AzureRmResourceGroup -Name $rgName
        $targetRg.Location = $targetLocation

      
        $Script:resourceGroups += $targetRg
      }

    }

    Function Add-StorageList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [String] $storName  
      )

      $storCheck = $storageAccounts | Where-Object { $_.StorageAccountName -eq $storName }
  
      if ( $storCheck -eq $null )
      {
        $targetStor = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storName }
        $targetStor.Location = $targetLocation

        $Script:storageAccounts += $targetStor
      }
    }

  
    #VM
    Add-ResourceGroupList -rgName $vm.ResourceGroupName

    #AS
    if ($vm.AvailabilitySetReference -ne $null)
    {
    
      Add-ResourceGroupList -rgName $vm.AvailabilitySetReference.Id.Split("/")[4]
    
    }
   

    #NIC
    if ($vm.NetworkInterfaceIDs -ne $null)
    {
      foreach ( $nicId in $vm.NetworkInterfaceIDs )
      {
        Add-ResourceGroupList -rgName $nicId.Split("/")[4]
            
        $nic = Get-AzureRmNetworkInterface | Where-Object { $_.Id -eq $nicId }

        foreach ( $ipConfig in $nic.IpConfigurations )
        {
          #LB
          foreach( $lbp in $ipConfig.LoadBalancerBackendAddressPools)
          {   
            Add-ResourceGroupList -rgName $lbp.Id.Split("/")[4]
            
            #PIP-LB
            $lb = Get-AzureRmLoadBalancer -Name $lbp.Id.Split("/")[8] -ResourceGroupName $lbp.Id.Split("/")[4]
            foreach ( $fip in $lb.FrontendIpConfigurations )
            {
               Add-ResourceGroupList -rgName $fip.PublicIpAddress.Id.Split("/")[4]
            }  
          }

          #VN
          Add-ResourceGroupList -rgName $ipConfig.Subnet.Id.Split("/")[4]
            

          #NSG-VN
          $vn = Get-AzureRmVirtualNetwork -Name $ipConfig.Subnet.Id.Split("/")[8] -ResourceGroupName $ipConfig.Subnet.Id.Split("/")[4]

          foreach ( $subnet in $vn.Subnets)
          {
            if ( $subnet.NetworkSecurityGroup -ne $null)
            {
               Add-ResourceGroupList -rgName $subnet.NetworkSecurityGroup.Id.Split("/")[4]
            }
          }
         

          #PIP-nic
          if ($ipConfig.PublicIpAddress -ne $null)
          {
            Add-ResourceGroupList -rgName $ipConfig.PublicIpAddress.Id.Split("/")[4]
          }
        }

      
        #NSG-nic
        if ($nic.NetworkSecurityGroup -ne $null)
        {
          Add-ResourceGroupList -rgName $nic.NetworkSecurityGroup.Id.Split("/")[4]
        }

      }
    }


    #Get the Storage Accountes related to this VM

    #OSDisk
    $osuri = $vm.StorageProfile.OsDisk.Vhd.Uri
    if ( $osuri -match "https" ) {
    $osstorname = $osuri.Substring(8, $osuri.IndexOf(".blob") - 8)}
    else {
      $osstorname = $osuri.Substring(7, $osuri.IndexOf(".blob") - 7)
    }
    Add-StorageList -storName $osstorname


    #DataDisk
    foreach($dataDisk in $vm.StorageProfile.DataDisks)
    {
      $datauri = $dataDisk.Vhd.Uri
      if ( $datauri -match "https" ) {
      $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
      else {
        $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
      }
      Add-StorageList -storName $datastorname
    }
  }
  else
  {
    Function Add-RenameResourceGroupList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [PSObject] $renameInfo
      )

      $rgCheck = $resourceGroups | Where-Object { $_.ResourceGroupName -eq $renameInfo.DestinationResourceGroup }

      if ( $rgCheck -eq $null )
      {
        $targetRg = Get-AzureRmResourceGroup -Name $renameInfo.SourceResourceGroup

        $targetRg.Location = $targetLocation
        $targetRg.ResourceGroupName = $renameInfo.DestinationResourceGroup
      
        $Script:resourceGroups += $targetRg
      }

    }

    Function Add-RenameStorageList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [PSObject] $renameInfo  
      )

      $storCheck = $storageAccounts | Where-Object { $_.StorageAccountName -eq $renameInfo.DestinationName }
  
      if ( $storCheck -eq $null )
      {
        $targetStor = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $renameInfo.SourceName }
        $targetStor.Location = $targetLocation
        $targetStor.StorageAccountName = $renameInfo.DestinationName.ToLower()
        $targetStor.ResourceGroupName = $renameInfo.DestinationResourceGroup

        $Script:storageAccounts += $targetStor
      }
    }
  
    ForEach ( $RenameInfo in $RenameInfos )
    {
      Add-RenameResourceGroupList -renameInfo $RenameInfo

      if ( $RenameInfo.ResourceType -eq "storageAccounts" )
      {
        Add-RenameStorageList -renameInfo $RenameInfo
      }
    }
  }


  ####Create Resource Group and Storage Account in Destination####

  ##Update Progress
  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Creating Resource Groups" -percentComplete 50

  Set-AzureRmContext -Context $DestContext | Out-Null

  #Create Resource Group if Not Exist
  Foreach ($rg in $resourceGroups)
  {
    $rgCheck = Get-AzureRmResourceGroup -Name $rg.ResourceGroupName -ErrorAction Ignore

    if ($rgCheck -eq $null)
    {
      New-AzureRmResourceGroup -Name $rg.ResourceGroupName -Location $rg.Location | Out-Null
    }

  }

  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Creating Storage Accounts" -percentComplete 75

  #Create Storage if Not Exist
  Foreach ($storage in $storageAccounts)
  {
    $storageCheck = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storage.StorageAccountName}

    if ( $storageCheck -eq $null )
    {
      $storageAvailability = Get-AzureRmStorageAccountNameAvailability -Name $storage.StorageAccountName
      if ($storageAvailability.NameAvailable -eq $false)
      {
        Throw ("The storage account " + $storage.StorageAccountName + " cannot be created because " + $storageAvailability.Reason)
      }
      else
      {
        $skuName = $storage.Sku.Tier.ToString() + "_" + $storage.Sku.Name.ToString().Replace($storage.Sku.Tier.ToString(), "")
       
        #Here is a version difference the command is for 3.0
        $rgCheck = Get-AzureRmResourceGroup -Name $storage.ResourceGroupName -ErrorAction Ignore

        if ($rgCheck -eq $null)
        {
          New-AzureRmResourceGroup -Name $storage.ResourceGroupName -Location $storage.Location | Out-Null
        } 
       
        New-AzureRmStorageAccount -Name $storage.StorageAccountName -ResourceGroupName $storage.ResourceGroupName -Location $storage.Location -SkuName $skuName | Out-Null
      }
    }

  }

  ##Update Progress
  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Succeeded" -percentComplete 100


}

function Start-AzureRmVMMigrationVhdCopy
{
  Param(
    [Parameter(Mandatory=$true)]
    [PSObject] $vm,

    [Parameter(Mandatory=$true)]
    [String] $targetLocation,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $SrcContext,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $DestContext,
  
    [Parameter(Mandatory=$false)]
    [AllowNull()]
    [Object[]]
    $RenameInfos  

  )

  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "-vm : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-DestContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext"
    }
  }

  if ($RenameInfos.Count -ne 0)
  {
    ForEach( $RenameInfo in $RenameInfos )
    {
      if ( $RenameInfo.GetType().FullName -notmatch "ResourceProfile" )
      {
        Throw "-RenameInfos : parameter type is invalid. Please enter the right parameter type: ResourceProfile"
      }
    }
  }


  Class StorageInfo
  {
    [String] $SrcAccountName
    [String] $SrcAccountSecret
    [String] $SrcContainerName
    [String] $SrcBlobName
    [String] $DestAccountName
    [String] $DestAccountSecret
    [String] $DestContainerName
    [String] $DestBlobName
    [PSObject] $Snapshot
    [Int64] $BlobActualBytes
    [bool] $CopyComplete = $false
    [bool] $IsOSDisk = $false
    [Int] $Lun
  }


  $StorageInfos = @()

  ##Update Progress
  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Copying VHDs" -percentComplete 20
  Write-Progress -Id 20 -ParentId 0 -activity "VHDs Copy" -status "Started" -percentComplete 0
  $ProgressPreference = "SilentlyContinue"

  ####Get Storage Information####
  #OSDisk
  Set-AzureRmContext -Context $SrcContext | Out-Null
  $osDiskInfo = New-Object StorageInfo
  $osDiskInfo.IsOSDisk = $True

  $osuri = $vm.StorageProfile.OsDisk.Vhd.Uri
  if ( $osuri -match 'https' ) {
  $osDiskInfo.SrcAccountName = $osuri.Substring(8, $osuri.IndexOf('.blob') - 8)}
  else {
    $osDiskInfo.SrcAccountName = $osuri.Substring(7, $osuri.IndexOf('.blob') - 7)
  }
  $osDiskInfo.SrcContainerName = $osuri.Split('/')[3]
  $osDiskInfo.SrcBlobName = $osuri.Split('/')[$osuri.Split('/').Count - 1]

  $osStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $osDiskInfo.SrcAccountName }
  $osDiskInfo.SrcAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $osStorAccount.ResourceGroupName -Name $osStorAccount.StorageAccountName)[0].Value

  #Destination Storage Information

  $osDiskInfo.DestBlobName = $osDiskInfo.SrcBlobName
  $osDiskInfo.DestContainerName = $osDiskInfo.SrcContainerName

  if ($RenameInfos.Count -eq 0)
  {
    Set-AzureRmContext -Context $DestContext | Out-Null
    $osDiskInfo.DestAccountName = $osDiskInfo.SrcAccountName
    $osStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $osDiskInfo.DestAccountName }
    if ( $osStorAccount -eq $null )
    { Throw ("The storage account: " + $osDiskInfo.DestAccountName  +"has not been created yet. Please create before vhd copy.") } 
    $osDiskInfo.DestAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $osStorAccount.ResourceGroupName -Name $osStorAccount.StorageAccountName)[0].Value
  }
  $StorageInfos += $osDiskInfo
  #DataDisk
  foreach($dataDisk in $vm.StorageProfile.DataDisks)
  {
    $dataDiskInfo = New-Object StorageInfo
    $dataDiskInfo.Lun = $dataDisk.Lun
   
    Set-AzureRmContext -Context $SrcContext | Out-Null
    $datauri = $dataDisk.Vhd.Uri
    if ( $datauri -match 'https' ) {
    $dataDiskInfo.SrcAccountName = $datauri.Substring(8, $datauri.IndexOf('.blob') - 8)}
    else {
      $dataDiskInfo.SrcAccountName = $datauri.Substring(7, $datauri.IndexOf('.blob') - 7)
    }
    $dataDiskInfo.SrcContainerName = $datauri.Split('/')[3]
    $dataDiskInfo.SrcBlobName = $datauri.Split('/')[$datauri.Split('/').Count - 1]

    $dataStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $dataDiskInfo.SrcAccountName }
    $dataDiskInfo.SrcAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $dataStorAccount.ResourceGroupName -Name $dataStorAccount.StorageAccountName)[0].Value

    #Destination Storage Information
   
    $dataDiskInfo.DestBlobName = $dataDiskInfo.SrcBlobName
    $dataDiskInfo.DestContainerName = $dataDiskInfo.SrcContainerName

    if ( $RenameInfos.Count -eq 0 )
    {
     
      Set-AzureRmContext -Context $DestContext | Out-Null
      $dataDiskInfo.DestAccountName = $dataDiskInfo.SrcAccountName
      $dataStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $dataDiskInfo.DestAccountName }
      if ( $dataStorAccount -eq $null ) 
      { Throw ("The storage account: " + $dataDiskInfo.DestAccountName  +"has not been created yet. Please create before vhd copy.")}
      $dataDiskInfo.DestAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $dataStorAccount.ResourceGroupName -Name $dataStorAccount.StorageAccountName)[0].Value
    }

    $StorageInfos += $dataDiskInfo
  }

  ####Handle for Rename
  if ( $RenameInfos.Count -ne 0 )
  {
    Set-AzureRmContext -Context $DestContext | Out-Null
    ForEach ( $stor in $StorageInfos )
    {
      $renameInfo = $RenameInfos | Where-Object { ( $_.SourceName -eq $stor.SrcAccountName ) -and ( $_.ResourceType -eq "storageAccounts" ) }
      if ( $renameInfo -ne $null )
      {
        $stor.DestAccountName = $renameInfo.Destinationname
      }
      $storAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $stor.DestAccountName }
      if ( $storAccount -eq $null )
      { Throw ("The storage account: " + $stor.DestAccountName  +"has not been created yet. Please create before vhd copy.") } 

      $stor.DestAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $storAccount.ResourceGroupName -Name $storAccount.StorageAccountName)[0].Value
    }
  }


  ####Start Vhds Copy####

  Foreach ( $vhd in $StorageInfos )
  {
    $srcStorageContext = New-AzureStorageContext -StorageAccountName $vhd.SrcAccountName -StorageAccountKey $vhd.SrcAccountSecret -Environment $SrcContext.Environment
    $destStorageContext = New-AzureStorageContext -StorageAccountName $vhd.DestAccountName -StorageAccountKey $vhd.DestAccountSecret -Environment $DestContext.Environment

    $srcBlob = Get-AzureStorageBlob -Blob $vhd.SrcBlobName -Container $vhd.SrcContainerName -Context $srcStorageContext
   
    $destBlob = Get-AzureStorageBlob -Blob $vhd.DestBlobName -Container $vhd.DestContainerName -Context $destStorageContext -ErrorAction Ignore
   
    while ( $destBlob -ne $null )
    {
      $vhd.DestBlobName = $vhd.DestBlobName.Replace(".vhd","") + (Get-Random -Minimum 1 -Maximum 99) + ".vhd"
      $destBlob = Get-AzureStorageBlob -Blob $vhd.DestBlobName -Container $vhd.DestContainerName -Context $destStorageContext -ErrorAction Ignore
    }

    $vhd.snapShot = $srcBlob.ICloudBlob.CreateSnapshot()
    $vhd.BlobActualBytes = 0
    $srcBlob.ICloudBlob.GetPageRanges() | ForEach-Object { $vhd.BlobActualBytes += 12 + $_.EndOffset - $_.StartOffset}  


    $containerCheck = Get-AzureStorageContainer -Name $vhd.DestContainerName -Context $destStorageContext -ErrorAction Ignore
    if ($containerCheck -eq $null)
    {
      New-AzureStorageContainer -Name $vhd.DestContainerName -Context $destStorageContext -Permission Off | Out-Null     
    }

    Start-AzureStorageBlobCopy -ICloudBlob $vhd.snapShot -Context $srcStorageContext -DestContainer $vhd.DestContainerName -DestBlob $vhd.DestBlobName -DestContext $destStorageContext | Out-Null

  }

  $vm | Add-Member -Name StorageInfos -Value $StorageInfos -MemberType NoteProperty
  MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VhdCopy" -phaseStatus Started

  ####Copy Status Check###
  $copyComplete = $false
  $allSucceed = $True
  $failedVHDs = @()

  $dataDiskUris = New-Object string[] $vm.StorageProfile.DataDisks.Count

  $ProgressPreference = "Continue"
  Write-Progress -Id 20 -ParentId 0 -activity "VHDs Copy" -status "Copying" -percentComplete 0

  $totalDiskNumber = $StorageInfos.Count
  $completeDisk = 0


  while ( !$copyComplete )
  {

    $id = 20
    $copyComplete = $True
    $completeInThisRound = $false

    Start-Sleep -Seconds 0.5

    Foreach ( $vhd in $StorageInfos)
    {
    
      $id ++
      if ( $vhd.CopyComplete -ne $True )
      {
        $destStorageContext = New-AzureStorageContext -StorageAccountName $vhd.DestAccountName -StorageAccountKey $vhd.DestAccountSecret -Environment $DestContext.Environment
      
        $ProgressPreference = "SilentlyContinue"
        $destBlob = Get-AzureStorageBlob -Blob $vhd.DestBlobName -Container $vhd.DestContainerName -Context $destStorageContext
        $ProgressPreference = "Continue"

        switch ($destBlob.ICloudBlob.CopyState.Status)
        {
          'Pending' {
                     $copyComplete = $false
                                        
                     $copyPercentage = [math]::Round(($destBlob.ICloudBlob.CopyState.BytesCopied / $vhd.BlobActualBytes * 100),2)
                     if ($copyPercentage -ge 100)
                     {
                       $copyPercentage = 100
                     }
                     Write-Progress -id $id -parentId 20 -activity $vhd.DestBlobName -status "Copying" -percentComplete $copyPercentage
                  }
          'Success' {
                     $vhd.CopyComplete = $True
                     $completeInThisRound = $True
                     $completeDisk += 1

                     if ( $vhd.IsOSDisk )
                     {$osDiskUri = $destBlob.ICloudBlob.Uri.AbsoluteUri}
                     else
                     {$dataDiskUris[$vhd.Lun] = $destBlob.ICloudBlob.Uri.AbsoluteUri }
                     
                     $vhd.Snapshot.Delete()
                     Write-Progress -id $id -parentId 20 -activity $vhd.DestBlobName -status "Succeeded" -percentComplete 100
                  }
          'Failed'  {
                     $vhd.CopyComplete = $True
                     $completeInThisRound = $True
                     $completeDisk += 1
                     
                     $allSucceed = $false
                     $failedVHDs += $vhd.DestBlobName

                     $vhd.Snapshot.Delete()           
                     Write-Progress -id $id -parentId 20 -activity $vhd.DestBlobName -status "Failed" -percentComplete 0
                  }
        }
      }
    
   
    }

    ##Update Progress
    if ($completeInThisRound)
    {
      $totalPercentage = [math]::Round(($completeDisk / $totalDiskNumber * 100),2)
      Write-Progress -id 20 -ParentId 0 -activity "VHDs Copy" -status "Copying" -percentComplete $totalPercentage
    }
  }

  Write-Progress -id 20 -ParentId 0 -activity "VHDs Copy" -status "Complete" -percentComplete 100

  $id = 20
  ForEach ( $vhd in $StorageInfos )
  {
    $id++
    Write-Progress -id $id -parentId 20 -activity $vhd.DestBlobName -Completed
  }

  #Check Copy fail exceptioon
  if (!$allSucceed)
  {
    Throw "Following VHDs copy failed:" + $failedVHDs
  }

  #return uris for VM building
  $diskUris = New-Object PSObject
  $diskUris | Add-Member -Name osDiskUri -Value $osDiskUri -MemberType NoteProperty
  $diskUris | Add-Member -Name dataDiskUris -Value $dataDiskUris -MemberType NoteProperty

  return $diskUris,$vm

}

function Start-AzureRmVMMigrationBuild
{
  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] $vm,

    [Parameter(Mandatory=$True)]
    [String] $targetLocation,

    [Parameter(Mandatory=$true)]
    [String] $osDiskUri,

    [Parameter(Mandatory=$false)]
    [String[]] $dataDiskUris,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $SrcContext,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $DestContext,
  
    [Parameter(Mandatory=$false)]
    [AllowNull()]
    [Object[]]
    $RenameInfos  

  )

  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "-vm : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-DestContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext"
    }
  }

  if ($RenameInfos.Count -ne 0)
  {
    ForEach( $RenameInfo in $RenameInfos )
    {
      if ( $RenameInfo.GetType().FullName -notmatch "ResourceProfile" )
      {
        Throw "-RenameInfos : parameter type is invalid. Please enter the right parameter type: ResourceProfile"
      }
    }
  }

  ##Write Progress
  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Building VM" -percentComplete 70
  Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Started" -percentComplete 0


  Class ResourceProfile
  {
    [String] $ResourceType
    [String] $SourceResourceGroup
    [String] $DestinationResourceGroup
    [String] $SourceName
    [String] $DestinationName
    [String] $DnsName
  }


  ##Get the coponents and resource groups
  Set-AzureRmContext -Context $SrcContext | Out-Null
  $Script:sourceResourceGroups = @()
  $Script:destinationResourceGroups = @()
  $Script:vmResources = @()

  if ( $RenameInfos.Count -eq 0)
  {
    Function Add-ResourceList
    {
      Param(
        [Parameter(Mandatory=$True)]
        [String] $resourceId
      )
   
      $rgCheck = $resourceGroups | Where-Object { $_ -eq $resourceId.Split("/")[4] }

      if ( $rgCheck -eq $null )
      {
        $Script:resourceGroups += $resourceId.Split("/")[4]
      }
   
      $resource = New-Object ResourceProfile
      $resource.SourceName = $resourceId.Split("/")[8]
      $resource.DestinationName = $resourceId.Split("/")[8]
      $resource.ResourceType = $resourceId.Split("/")[7]
      $resource.SourceResourceGroup = $resourceId.Split("/")[4]
      $resource.DestinationResourceGroup = $resourceId.Split("/")[4]
   
      $resourceCheck = $vmResources | Where-Object { ($_.SourceName -eq $resource.SourceName) -and ($_.ResourceType -eq $resource.ResourceType) -and ($_.SourceResourceGroup -eq $resource.SourceResourceGroup) }
   
      if ( $resourceCheck -eq $null )
      {
        $Script:vmResources += $resource
      }
    
    }

    ####Get VM Components####
    Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Getting VM Components" -percentComplete 10

    ##Handle Resource Group Dependencies: List Distinct Resource Group
    #VM
    $Script:resourceGroups = @()

    Add-ResourceList -resourceId $vm.Id

    #AS
    if ($vm.AvailabilitySetReference -ne $null)
    {
      Add-ResourceList -resourceId $vm.AvailabilitySetReference.Id
    }
   

    #NIC
    if ($vm.NetworkInterfaceIDs -ne $null)
    { 
      foreach ( $nicId in $vm.NetworkInterfaceIDs )
      {
        Add-ResourceList -resourceId $nicId
            
        $nic = Get-AzureRmNetworkInterface | Where-Object { $_.Id -eq $nicId }
     
        foreach ( $ipConfig in $nic.IpConfigurations )
        {
          #LB
          foreach( $lbp in $ipConfig.LoadBalancerBackendAddressPools)
          {   
            Add-ResourceList -resourceId $lbp.Id
            
            #PIP-LB
            $lb = Get-AzureRmLoadBalancer -Name $lbp.Id.Split("/")[8] -ResourceGroupName $lbp.Id.Split("/")[4]
                                  
            foreach ( $fip in $lb.FrontendIpConfigurations )
            {
               Add-ResourceList -resourceId $fip.PublicIpAddress.Id
            }  
          }

          #VN
         
          Add-ResourceList -resourceId $ipConfig.Subnet.Id

          #NSG-VN
          $vn = Get-AzureRmVirtualNetwork -Name $ipConfig.Subnet.Id.Split("/")[8] -ResourceGroupName $ipConfig.Subnet.Id.Split("/")[4]
            
          foreach ( $subnet in $vn.Subnets)
          {
            if ( $subnet.NetworkSecurityGroup -ne $null)
            {
              Add-ResourceList -resourceId $subnet.NetworkSecurityGroup.Id                
            }
          }
         

          #PIP-nic
          if ($ipConfig.PublicIpAddress -ne $null)
          {
            Add-ResourceList -resourceId $ipConfig.PublicIpAddress.Id
          }
        }
     
        #NSG-nic
        if ($nic.NetworkSecurityGroup -ne $null)
        {
          Add-ResourceList -resourceId $nic.NetworkSecurityGroup.Id
        }

      }
    }

    $Script:sourceResourceGroups = $resourceGroups
    $Script:destinationResourceGroups = $resourceGroups
  }
  else
  {
    Foreach ( $renameInfo in $RenameInfos)
    {
      $Script:sourceResourceGroups += $RenameInfo.SourceResourceGroup.ToLower()
      $Script:destinationResourceGroups += $RenameInfo.DestinationResourceGroup.ToLower()

      if ( $renameInfo.ResourceType -ne "storageAccounts" )
      {
        $Script:vmResources += $renameInfo
      }
    }

    $Script:sourceResourceGroups = $sourceResourceGroups | Select-Object -Unique
    $Script:destinationResourceGroups = $destinationResourceGroups | Select-Object -Unique
  }

  ####Get ARM Template and Modify####
  $SrcResourceList = New-Object PSObject
  $DestResourceList = New-Object PSObject

  $sourceParameters = New-Object PSObject

  $tempId = [guid]::NewGuid()

  Foreach ( $rg in $sourceResourceGroups ) 
  {
    #Get the Target Resource Group ARM Template
    New-Item -ItemType directory -Path "$Env:TEMP\AzureMigrationtool" -Force | Out-Null
    $Sourcetemplatepath = $Env:TEMP + "\AzureMigrationtool\$tempId" + "\Source" + $rg + ".json"

    Export-AzureRmResourceGroup -ResourceGroupName $rg -Path $Sourcetemplatepath -IncludeParameterDefaultValue -Force -WarningAction Ignore | Out-Null

    $sourceTemplate = Get-Content -raw -Path $Sourcetemplatepath | ConvertFrom-Json

    $paraMembers = $sourceTemplate.parameters | Get-Member -MemberType NoteProperty
  
    #Update the rename result in parameter
    foreach ( $pm in $paraMembers )
    {
      $pmName = $pm.Name
      if (( $pmName -match "_name" ) )
      {
        $sourceName = $pmName.Split("_")[1]
        for ( $i = 2; $i -lt ($pmName.Split("_").Count - 1); $i++ )
        {
          $sourceName = $sourceName + "-" + $pmName.Split("_")[$i]
        }
                 
        $targetResource = $vmResources | Where-Object { ($_.SourceName -eq $sourceName ) -and ( $_.SourceResourceGroup -eq $rg ) -and ( $_.ResourceType -eq $pmName.Split("_")[0] ) }
          
        if ( $targetResource -ne $null )
        {         
          $sourceTemplate.parameters.$pmName.defaultValue = $targetresource.DestinationName
        }            
      }

      $sourceParameters | Add-Member -Name $pmName -MemberType NoteProperty -Value $sourceTemplate.parameters.$pmName
    }

    $SrcResourceList | Add-Member -Name $rg -MemberType NoteProperty -Value $sourcetemplate
  }

  #Prepare the destination resource container
  ForEach ( $rg in $destinationResourceGroups )
  {
    $targetresources = New-Object PSObject
    $container = @()
    $targetresources | Add-Member -Name 'Phase1' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase2' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase3' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase4' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase5' -MemberType NoteProperty -Value $container

    $DestResourceList | Add-Member -Name $rg -MemberType NoteProperty -Value $targetresources
  }


  #Classify and Modify ARM Template
  ForEach ( $resource in $vmResources )
  {
    $name = ("_" + $resource.SourceName + "_").Replace("-","_")
    $srcRg = $resource.SourceResourceGroup
    $destRg = $resource.DestinationResourceGroup
  
    switch ($resource.ResourceType)
    {
      { $_ -in "publicIPAddresses", "networkSecurityGroups", "availabilitySets" } { $phase = 'Phase1' }
      'virtualNetworks' { $phase = 'Phase2' }
      'loadBalancers' { $phase = 'Phase3' }
      'networkInterfaces' { $phase = 'Phase4' }
      'virtualMachines' { $phase = 'Phase5' }
    }
  
    $resourcecheck = $DestResourceList.$destRg.$phase | Where-Object { ($_.name -match $name) -and ($_.type -match $resource.ResouceType) }
  
    if ( $resourcecheck -eq $null ) {

      switch ($resource.ResourceType)
      {
        'virtualMachines'
        {
          $c = $SrcResourceList.$srcRg.resources | Where-Object { ($_.name -match $name) -and ($_.type -match "Microsoft.Compute/virtualMachines") }

          if ($c -eq $null)
          {
            Throw ("Cannot find the virtual machine " + $resource.SourceName + " in source subscription.")
          }

          $crspropstorprofile = New-Object PSObject
          $crspropstorprofile | Add-Member -Name "osDisk" -MemberType NoteProperty -Value ($c.properties.storageProfile.osdisk | Select-Object -Property * -ExcludeProperty image)
          $crspropstorprofile | Add-Member -Name "dataDisks" -MemberType NoteProperty -Value $c.properties.storageProfile.dataDisks
          $crspropstorprofile.osdisk.createOption = "Attach"

          $ostype = $vm.StorageProfile.OsDisk.OsType.ToString()
    
          $crspropstorprofile.osdisk | Add-Member -Name "osType" -MemberType NoteProperty -Value $ostype -Force

          $crspropstorprofile.osdisk.vhd.uri = $osDiskUri
    
          if ($crspropstorprofile.dataDisks.count -ne 0) {
            foreach ($d in $crspropstorprofile.dataDisks) {
              $d.createOption = "Attach"
              $d.vhd.uri = $dataDiskUris[$d.lun]
            }
          }

          $crsprop = New-Object PSObject
          $crsprop | Add-Member -Name "hardwareProfile" -MemberType NoteProperty -Value $c.properties.hardwareProfile
          $crsprop | Add-Member -Name "storageProfile" -MemberType NoteProperty -Value $crspropstorprofile
          $crsprop | Add-Member -Name "networkProfile" -MemberType NoteProperty -Value $c.properties.networkProfile

          if (!($c.properties.availabilitySet -eq $null)) {
            $crsprop | Add-Member -Name "availabilitySet" -MemberType NoteProperty -Value $c.properties.availabilitySet
          }

          $crsDeps = @()

          $crs = New-Object PSObject
          $crs | Add-Member -Name "type" -MemberType NoteProperty -Value $c.type
          $crs | Add-Member -Name "name" -MemberType NoteProperty -Value $c.name
          $crs | Add-Member -Name "apiVersion" -MemberType NoteProperty -Value $c.apiVersion
          $crs | Add-Member -Name "location" -MemberType NoteProperty -Value $targetLocation
          $crs | Add-Member -Name "tags" -MemberType NoteProperty -Value $c.tags
          $crs | Add-Member -Name "properties" -MemberType NoteProperty -Value $crsprop
          $crs | Add-Member -Name "dependsOn" -MemberType NoteProperty -Value $crsDeps

          $destResourceList.$destRg.Phase5 += $crs
        }
        'publicIPAddresses'
        {
          $targetresource = $srcResourceList.$srcRg.resources | Where-Object { ($_.name -match $name) -and ($_.type -match $resource.ResourceType) }
          $targetresource.location = $targetLocation
          $targetresource.dependsOn = @()
        
          if (!([string]::IsNullOrEmpty($resource.DnsName)))
          {
            if ($targetResource.properties.dnsSettings -eq $null)
            {
              $dnsSettings = New-Object PSObject
              $dnsSettings | Add-Member -MemberType NoteProperty -Name domainNameLabel -Value $resource.DnsName
              $targetResource.properties | Add-Member -MemberType NoteProperty -Name dnsSettings -Value $dnsSettings
            }
            else
            {
              if ($targetResource.properties.dnsSettings.domainNameLabel -eq $null)
              {
                $targetResource.properties.dnsSettings | Add-Member -MemberType NoteProperty -Name domainNameLabel -Value $resource.DnsName
              }
              else
              {
                $targetResource.properties.dnsSettings.domainNameLabel = $resource.DnsName
              }
            }
          }
          else
          {
            $targetResource.properties = $targetResource.properties | Select-Object -Property * -ExcludeProperty "dnsSettings"
          }

          $destResourceList.$destRg.$phase += $targetresource      
        }    
        default
        {
          $targetresource = $srcResourceList.$srcRg.resources | Where-Object { ($_.name -match $name) -and ($_.type -match $resource.ResourceType) }
          $targetresource.location = $targetLocation
          $targetresource.dependsOn = @()
          $destResourceList.$destRg.$phase += $targetresource
        }
      }  
    }
  }


  ####Build Azure VM####
  Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Deploying VM" -percentComplete 40
  Set-AzureRmContext -Context $DestContext | Out-Null

  $SourceSubID = $SrcContext.Subscription.SubscriptionId
  $DestSubID = $DestContext.Subscription.SubscriptionId

  Class ResourceMember
  {
    [String] $Name
    [PSObject] $Parent
    [Object[]] $Layers
  }

  $progressPercentage = 40

  #VM Deploy by Phase
  For($k = 1; $k -le 5 ; $k++ )
  {
    $currentPhase = "Phase" + $k

    Foreach ( $rg in $destinationResourceGroups ) {
    
      if ( $destResourceList.$rg.$currentPhase.Count -ne 0 ){
  
        #Set Target ARM Template with source settings
        $targettemplate = New-Object PSObject
        $targettemplate | Add-Member -Name '$schema' -MemberType NoteProperty -Value "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#"
        $targettemplate | Add-Member -Name "contentVersion" -MemberType Noteproperty -Value "1.0.0.0"
        $targettemplate | Add-Member -Name "parameters" -MemberType Noteproperty -Value $null
        $targettemplate | Add-Member -Name "variables" -MemberType Noteproperty -Value $null
        $targettemplate | Add-Member -Name "resources" -MemberType Noteproperty -Value $null
    
        $targettemplate.resources = $destResourceList.$rg.$currentPhase

        #Get the related parameters
        $parameterList = @()
        ForEach ( $resource in $targettemplate.resources ) 
        {
          if ( $resource.name -match "\[parameters\('")
          {
            $parameterList += $resource.Name.Split("'")[1]
          }
                
          $resourceMembers = $resource.properties | Get-Member -MemberType NoteProperty
          $resourceChecks = @()
          ForEach ( $member in $resourceMembers)
          {
            $resourceCheck = New-Object ResourceMember
            $resourceCheck.Name = $member.Name
            $resourceCheck.Parent = $resource.properties
            $resourceCheck.Layers += $member.Name
          
            $resourceChecks += $resourceCheck 
          }
        
        
          While ( $resourceChecks.Count -ne 0 )
          {
            $newResourceMembers = @()
            ForEach ( $r in $resourceChecks )
            {
              ForEach ( $parent in $r.Parent )
              {
                $value = $parent.($r.Name)
              
                if ($value -ne $null)
                {
                  $type = $value.GetType()
                  Switch ($type.Name)
                  {
                    "PSCustomObject" 
                    {
                      $members = $value | Get-Member -MemberType NoteProperty
                      ForEach ( $member in $members)
                      {
                        $resourceCheck = New-Object ResourceMember
                        $resourceCheck.Name = $member.Name
                        $resourceCheck.Parent = $value
                      
                        foreach ($l in $r.Layers)
                        {
                          $resourceCheck.Layers += $l
                        }
                        $resourceCheck.Layers += $member.Name
          
                        $newResourceMembers += $resourceCheck
                      }
                    }
                    "Object[]"
                    {
                      ForEach ( $v in $value )
                      {
                        $members = $v | Get-Member -MemberType NoteProperty
                        ForEach ( $member in $members)
                        {
                          $resourceCheck = New-Object ResourceMember
                          $resourceCheck.Name = $member.Name
                          $resourceCheck.Parent = $v

                          foreach ($l in $r.Layers)
                          {
                            $resourceCheck.Layers += $l
                          }
                          $resourceCheck.Layers += $member.Name
          
                          $newResourceMembers += $resourceCheck
                        }
                      }
                    }
                    Default
                    {
                      #collect the required template
                      if ( $value -match "\[parameters\('" )
                      {
                        $parameterList += $value.Split("'")[1]
                    
                      }

                      #update resourceId to make it independent
                      if (($r.Name -eq "id") -and ($value -match "resourceId"))
                      {
                        $indexOfParameterBegin = $value.IndexOf("parameters('") 
                        $indexOfParameterEnd = $value.IndexOf("')",$indexOfParameterBegin) 
                        $parameterName = $value.Substring($indexOfParameterBegin + 12 , $indexOfParameterEnd - $indexOfParameterBegin -12) 
                        $parameterList += $parameterName

                        if( $parameterName.Split("_").Count -eq 3 )
                        {
                          $sourceName = $parameterName.Split("_")[1]
                        }
                        else
                        {
                          $sourceName = $parameterName.Split("_")[1]
                          for ( $i = 2; $i -lt ($parameterName.Split("_").Count - 1); $i++ )
                          {
                            $sourceName = $sourceName + "-" + $parameterName.Split("_")[$i]
                          }
                        }
            
                        $targetResource = $vmResources | Where-Object { ($_.SourceName -eq $sourceName ) -and ( $_.ResourceType -eq $parameterName.Split("_")[0] ) }
                      
                        if ($targetResource -eq $null )
                        {
                          Throw ("Cannot find the target resource for the parameter: " + $parameterName)
                        }
                      
                        if ($targetResource.count -gt 1)
                        {
                          $indexOfParameterBegin = $resource.Name.IndexOf("parameters('") 
                          $indexOfParameterEnd = $resource.Name.IndexOf("')",$indexOfParameterBegin) 
                          $baseParameterName = $resource.Name.Substring($indexOfParameterBegin + 12 , $indexOfParameterEnd - $indexOfParameterBegin -12) 
                        
                          $baseResource = $vmResources | Where-Object {($resource.type -match $_.ResourceType) -and ( $_.DestinationName -eq $sourceParameters.$baseParameterName) -and ( $_.DestinationResourceGroup -eq $rg )}
                          $targetResource = $vmResources | Where-Object { ($_.SourceName -eq $sourceName ) -and ( $_.ResourceType -eq $parameterName.Split("_")[0] ) -and ( $_.SourceResourceGroup -eq $baseResource.SourceResourceGroup ) }
                        }
     
                        $newValue = $value.Replace("resourceId(", "resourceId('" + $targetResource.DestinationResourceGroup + "', ")
                      
                        $numberOfLayer = 0
                        foreach ($layer in $r.Layers)
                        {
                          $name = "Layer" + $numberOfLayer
                          New-Variable -Name $name -Value $layer -Force
                          $numberOfLayer++
                        }
                      
                        #update the resource id value
                        switch($r.Layers.count)
                        {
                          1
                          { ($resource.properties | Where-Object { $_.$Layer0 -eq $value }).$Layer0 = $newValue }
                          2
                          { ($resource.properties.$Layer0 | Where-Object { $_.$Layer1 -eq $value }).$Layer1 = $newValue}
                          3
                          { ($resource.properties.$Layer0.$Layer1 | Where-Object { $_.$Layer2 -eq $value }).$Layer2 = $newValue}
                          4
                          { ($resource.properties.$Layer0.$Layer1.$Layer2 | Where-Object { $_.$Layer3 -eq $value }).$Layer3 = $newValue }
                          Default
                          { Thow "Layer OverFlow" }
                        }                     
                      }
                    }
                  } 
                }
              }
            }
          
            $resourceChecks = $newResourceMembers       
          }
        }
      
        #Collect the required parameters into template
        if ($parameterList.Count -ne 0)
        {
          $parameterList = $parameterList | Select-Object -Unique

          $targetparameters = $sourceParameters | Select-Object -Property $parameterList
          $targetparpmembers = $targetparameters | Get-Member -MemberType NoteProperty
          Foreach ( $tm in $targetparpmembers ) {
            $tmname = $tm.Name
            if (($targetparameters.$tmname.defaultValue -ne $null) -and ( $targetparameters.$tmname.type -eq "String" ) -and ( $tmname -match "_id" ) ) 
            {
              $targetparameters.$tmname.defaultValue = $targetparameters.$tmname.defaultValue.Replace("/subscriptions/$SourceSubID","/subscriptions/$DestSubID")
          
              $targetResource = $vmResources | Where-Object { ($_.SourceName -eq $targetparameters.$tmname.defaultValue.Split("/")[8] ) -and ( $_.SourceResourceGroup -eq $targetparameters.$tmname.defaultValue.Split("/")[4] ) -and ( $_.ResourceType -eq $targetparameters.$tmname.defaultValue.Split("/")[7] ) }
          
              if ( $targetResource -eq $null )
              { Throw ("Cannot find the resource Id in this deployment: " + $targetparameters.$tmname.defaultValue) }
          
              $targetparameters.$tmname.defaultValue = $targetparameters.$tmname.defaultValue.Replace("/resourceGroups/"+ $targetResource.SourceResourceGroup,"/resourceGroups/" + $targetResource.DestinationResourceGroup)
              $targetparameters.$tmname.defaultValue = $targetparameters.$tmname.defaultValue.Replace("/" + $targetResource.ResourceType + "/"+ $targetResource.SourceName,"/" + $targetResource.ResourceType + "/"+ $targetResource.DestinationName)   
            }
            if ( ($tmname -match "primary") -and ( $targetparameters.$tmname.type -eq "Bool" ) ) 
            {
              $targetparameters.$tmname.defaultValue = $True
            }
          }

          $targettemplate.parameters = $targetparameters
        }
      
        #Output the json template
        $targettemplatename = "Target" + $rg + $currentPhase + ".json"
      
        $targetjson = $targettemplate | ConvertTo-Json -Depth 9
        $targettemplatepath = $Env:TEMP + "\AzureMigrationtool\$tempId" + "\" + $targettemplatename
        $targetjson -replace "\\u0027", "'" | Out-File $targettemplatepath
      
        #Actual ARM deployment
        New-AzureRmResourceGroupDeployment -ResourceGroupName $rg -TemplateFile $targettemplatepath | Out-Null    

      }
    }

    $progressPercentage += 10

    if ($progressPercentage -ge 90)
    {
      $progressPercentage = 90
    }

    Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Deploying VM" -percentComplete $progressPercentage
  }
  MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VMBuild" -phaseStatus Succeed

  ####Validate the VM Deployment####
  Set-AzureRmContext -Context $DestContext | Out-Null
  Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Validating deployment" -percentComplete 95

  $vmDestination =  $vmResources | Where-Object { ($_.SourceName -eq $vm.Name) -and ($_.SourceResourceGroup -eq $vm.ResourceGroupName) -and ( $_.ResourceType -eq "virtualMachines") } 
  $destVM = Get-AzureRmVM -ResourceGroupName $vmDestination.DestinationResourceGroup -Name $vmDestination.DestinationName

  if ( ($destVM -ne $null) -and ( $destVM.ProvisioningState -eq "Succeeded" ))
  {
    Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Succeeded" -percentComplete 100
  
    $templatepath = $Env:TEMP + "\AzureMigrationtool\$tempId"
    Remove-Item $templatepath* -Force -Recurse

  }
  else
  {
    $templatepath = $Env:TEMP + "\AzureMigrationtool\$tempId"
    Remove-Item $templatepath* -Force -Recurse
    MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PostValidate" -completed -phaseStatus Failed
    Throw "The VM Migration is Failed."
  }

  MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PostValidate" -phaseStatus Succeed -completed 
}

Function Set-AzureRmVMMigrationRename
{
  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] $vm,

    [Parameter(Mandatory=$True)]
    [String] $targetLocation,

    [Parameter(Mandatory=$true)]
    [PSObject] $SrcContext
  )

  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    { 
      Throw "-vm : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please input the right parameter type: Microsoft.Azure.Commands.Profile.Models.PSAzureContext."
    }
  }

  Class ResourceProfile
  {
    [String] $ResourceType
    [String] $SourceResourceGroup
    [String] $DestinationResourceGroup
    [String] $SourceName
    [String] $DestinationName
    [String] $DnsName
  }

  Function Add-ResourceList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $resourceId
    )
    
    $resource = New-Object ResourceProfile
    $resource.SourceName = $resourceId.Split("/")[8]
    $resource.ResourceType = $resourceId.Split("/")[7]
    $resource.SourceResourceGroup = $resourceId.Split("/")[4].ToLower()
   
    $resourceCheck = $vmResources | Where-Object { ($_.SourceName -eq $resource.SourceName) -and ($_.ResourceType -eq $resource.ResourceType) -and ($_.SourceResourceGroup -eq $resource.SourceResourceGroup) }
   
    if ( $resourceCheck -eq $null )
    {
      if ($resource.ResourceType -eq "publicIPAddresses")
      {
        $pip = Get-AzureRmPublicIpAddress -Name $resource.SourceName -ResourceGroupName $resource.SourceResourceGroup
        $resource.DnsName = $pip.DnsSettings.DomainNameLabel
      }
      $Script:vmResources += $resource
    }
  }

  Function Add-StorageList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $storName   
    )

    $storCheck = $vmResources | Where-Object { ($_.SourceName -eq $storName) -and ($_.ResourceType -eq "storageAccounts" ) }

    if ( $storCheck -eq $null )
    {
      $targetStor = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storName }
      
      $resource = New-Object ResourceProfile
      $resource.SourceName = $targetStor.StorageAccountName
      $resource.ResourceType = "storageAccounts"
      $resource.SourceResourceGroup = $targetStor.ResourceGroupName

      $Script:vmResources += $resource
    }
  }

  ####Get VM Components####
  Set-AzureRmContext -Context $SrcContext | Out-Null

  #VM
  $Script:vmResources = @()

  Add-ResourceList -resourceId $vm.Id

  #AS
  if ($vm.AvailabilitySetReference -ne $null)
  {
    Add-ResourceList -resourceId $vm.AvailabilitySetReference.Id
  }
   

  #NIC
  if ($vm.NetworkInterfaceIDs -ne $null)
  { 
    foreach ( $nicId in $vm.NetworkInterfaceIDs )
    {
      Add-ResourceList -resourceId $nicId
            
      $nic = Get-AzureRmNetworkInterface | Where-Object { $_.Id -eq $nicId }
     
      foreach ( $ipConfig in $nic.IpConfigurations )
      {
         #LB
         foreach( $lbp in $ipConfig.LoadBalancerBackendAddressPools)
         {   
            Add-ResourceList -resourceId $lbp.Id
            
            #PIP-LB
            $lb = Get-AzureRmLoadBalancer -Name $lbp.Id.Split("/")[8] -ResourceGroupName $lbp.Id.Split("/")[4]
                                  
            foreach ( $fip in $lb.FrontendIpConfigurations )
            {
               Add-ResourceList -resourceId $fip.PublicIpAddress.Id
            }  
         }

         #VN
         
         Add-ResourceList -resourceId $ipConfig.Subnet.Id

         #NSG-VN
         $vn = Get-AzureRmVirtualNetwork -Name $ipConfig.Subnet.Id.Split("/")[8] -ResourceGroupName $ipConfig.Subnet.Id.Split("/")[4]
            
         foreach ( $subnet in $vn.Subnets)
         {
            if ( $subnet.NetworkSecurityGroup -ne $null)
            {
              Add-ResourceList -resourceId $subnet.NetworkSecurityGroup.Id                
            }
         }
         

         #PIP-nic
         if ($ipConfig.PublicIpAddress -ne $null)
         {
           Add-ResourceList -resourceId $ipConfig.PublicIpAddress.Id
         }
      }
     
      #NSG-nic
      if ($nic.NetworkSecurityGroup -ne $null)
      {
         Add-ResourceList -resourceId $nic.NetworkSecurityGroup.Id
      }

    }
  }

  #OSDisk
  $osuri = $vm.StorageProfile.OsDisk.Vhd.Uri
  if ( $osuri -match "https" ) {
  $osstorname = $osuri.Substring(8, $osuri.IndexOf(".blob") - 8)}
  else {
    $osstorname = $osuri.Substring(7, $osuri.IndexOf(".blob") - 7)
  }
  Add-StorageList -storName $osstorname


  #DataDisk
  foreach($dataDisk in $vm.StorageProfile.DataDisks)
  {
    $datauri = $dataDisk.Vhd.Uri
    if ( $datauri -match "https" ) {
    $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
    else {
      $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
    }
    Add-StorageList -storName $datastorname
  }


  ####Rename Function####
  $RenameFunction = 
  {
    Class ResourceProfile
    {
      [String] $ResourceType
      [String] $SourceResourceGroup
      [String] $DestinationResourceGroup
      [String] $SourceName
      [String] $DestinationName
      [String] $DnsName
    }

    Function Rename {
      Param(
        [Parameter(Mandatory=$True)]
        [AllowNull()]
        [Object[]] 
        $vmResources
      )
      Add-Type -AssemblyName System.Windows.Forms
      Add-Type -AssemblyName System.Drawing
      $objForm = New-Object System.Windows.Forms.Form 
      $objForm.Text = "Azure Global Connection Center"
      $objForm.Size = New-Object System.Drawing.Size(800,600) 
      $objForm.StartPosition = "CenterScreen"

      $objForm.KeyPreview = $True
      $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
          {
            $objForm.DialogResult = "OK"
            $objForm.Close()
          }
      })

      $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
      {$objForm.Close()}})

      $objForm.BackColor = "#1F4E79"

      $Buttonfont = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Bold)
      $OKButton = New-Object System.Windows.Forms.Button
      $OKButton.Location = New-Object System.Drawing.Size(10,500)
      $OKButton.Size = New-Object System.Drawing.Size(180,40)
      $OKButton.Text = "OK"
      $OKButton.Font = $Buttonfont
      $OKButton.BackColor = "Gainsboro"

      $OKButton.Add_Click(
        {    
          $objForm.DialogResult = "OK"
          $objForm.Close()
      })

      $objForm.Controls.Add($OKButton)

      $CancelButton = New-Object System.Windows.Forms.Button
      $CancelButton.Location = New-Object System.Drawing.Size(200,500)
      $CancelButton.Size = New-Object System.Drawing.Size(180,40)
      $CancelButton.Text = "Cancel"
      $CancelButton.Font = $Buttonfont
      $CancelButton.BackColor = "Gainsboro"

      $CancelButton.Add_Click({$objForm.Close()})
      $objForm.Controls.Add($CancelButton)

      $objFont = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Italic)
      $objLabel = New-Object System.Windows.Forms.Label
      $objLabel.Location = New-Object System.Drawing.Size(10,20) 
      $objLabel.AutoSize = $True
      $objLabel.BackColor = "Transparent"
      $objLabel.ForeColor = "White"
      $objLabel.Font = $objFont
      $objLabel.Text = "Please Check the Name of Following Resources"
      $objForm.Controls.Add($objLabel) 

      $objFont2 = New-Object System.Drawing.Font("Arial",10,[System.Drawing.FontStyle]::Regular)
      $objLabel2 = New-Object System.Windows.Forms.Label
      $objLabel2.Location = New-Object System.Drawing.Size(10,55) 
      $objLabel2.AutoSize = $True
      $objLabel2.BackColor = "Transparent"
      $objLabel2.ForeColor = "LightSteelBlue"
      $objLabel2.Font = $objFont2
      $objLabel2.Text = "Resource List"
      $objForm.Controls.Add($objLabel2) 

      $objListbox = New-Object System.Windows.Forms.DataGridView -Property @{
        ColumnHeadersVisible = $true
        RowHeadersVisible = $false
        location = New-Object System.Drawing.Size(10,80)
        Size = New-Object System.Drawing.Size(750,220)
        AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
        EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
        Height = 320
        Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Regular)
        AllowUserToAddRows = $false
      }

      $objListbox.ColumnCount = 5

      $objListbox.EnableHeadersVisualStyles = $false
      $objListbox.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
      $objListbox.ColumnHeadersDefaultCellStyle.ForeColor = "MidnightBlue"
  
      $objListbox.Columns[0].Name = "ResourceType"
      $objListbox.Columns[0].ReadOnly = $True
      $objListbox.Columns[0].DefaultCellStyle.BackColor = "Gainsboro"

      $objListbox.Columns[1].Name = "SoureResourceGroup"
      $objListbox.Columns[1].ReadOnly = $True
      $objListbox.Columns[1].DefaultCellStyle.BackColor = "Gainsboro"
  
      $objListbox.Columns[2].Name = "DestinationResourceGroup"
      $objListbox.Columns[2].DefaultCellStyle.BackColor = "White"

      $objListbox.Columns[3].Name = "SourceName"
      $objListbox.Columns[3].ReadOnly = $True
      $objListbox.Columns[3].DefaultCellStyle.BackColor = "Gainsboro"
  
      $objListbox.Columns[4].Name = "DestinationName"
      $objListbox.Columns[4].DefaultCellStyle.BackColor = "White"

      $vmResources | ForEach { $objListbox.rows.Add( $_.ResourceType , $_.SourceResourceGroup, $_.SourceResourceGroup, $_.SourceName, $_.SourceName )  } | Out-Null
  
      $objForm.Controls.Add($objListbox) 
    
      $objLabel3 = New-Object System.Windows.Forms.Label
      $objLabel3.Location = New-Object System.Drawing.Size(10,325) 
      $objLabel3.AutoSize = $True
      $objLabel3.BackColor = "Transparent"
      $objLabel3.ForeColor = "LightSteelBlue"
      $objLabel3.Font = $objFont2
      $objLabel3.Text = "DNS Name List"
      $objForm.Controls.Add($objLabel3) 
        
      $objDnsbox = New-Object System.Windows.Forms.DataGridView -Property @{
        ColumnHeadersVisible = $true
        RowHeadersVisible = $false
        location = New-Object System.Drawing.Size(10,350)
        Size = New-Object System.Drawing.Size(750,100)
        AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
        EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
        Height = 320
        Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Regular)
        AllowUserToAddRows = $false
      }
    
      $objDnsbox.ColumnCount = 5

      $objDnsbox.EnableHeadersVisualStyles = $false
      $objDnsbox.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
      $objDnsbox.ColumnHeadersDefaultCellStyle.ForeColor = "MidnightBlue"
  
      $objDnsbox.Columns[0].Name = "ResourceType"
      $objDnsbox.Columns[0].ReadOnly = $True
      $objDnsbox.Columns[0].DefaultCellStyle.BackColor = "Gainsboro"

      $objDnsbox.Columns[1].Name = "SoureResourceGroup"
      $objDnsbox.Columns[1].ReadOnly = $True
      $objDnsbox.Columns[1].DefaultCellStyle.BackColor = "Gainsboro"

      $objDnsbox.Columns[2].Name = "SourceName"
      $objDnsbox.Columns[2].ReadOnly = $True
      $objDnsbox.Columns[2].DefaultCellStyle.BackColor = "Gainsboro"
    
      $objDnsbox.Columns[3].Name = "SourceDNSName"
      $objDnsbox.Columns[3].ReadOnly = $True
      $objDnsbox.Columns[3].DefaultCellStyle.BackColor = "Gainsboro"
    
      $objDnsbox.Columns[4].Name = "DestinationDNSName"
      $objDnsbox.Columns[4].DefaultCellStyle.BackColor = "White"
    
      $vmResources | Where-Object {$_.ResourceType -eq "publicIPAddresses"} | ForEach { $objDnsbox.rows.Add( $_.ResourceType , $_.SourceResourceGroup, $_.SourceName, $_.DNSName, $_.DNSName )  } | Out-Null
    
      $objForm.Controls.Add($objDnsbox)

      $objForm.Add_Shown({$objForm.Activate()})

      [void] $objForm.ShowDialog()

      if ( $objForm.DialogResult -eq "OK" ) {

        $renameInfos = @()
        for ( $i = 0; $i -lt $objListbox.RowCount; $i ++ )
        {
          $renameInfo = New-Object ResourceProfile
          $renameInfo.ResourceType = $objListbox.Rows[$i].Cells[0].Value
          $renameInfo.SourceResourceGroup = $objListbox.Rows[$i].Cells[1].Value
          $renameInfo.DestinationResourceGroup = $objListbox.Rows[$i].Cells[2].Value
          $renameInfo.SourceName = $objListbox.Rows[$i].Cells[3].Value
          $renameInfo.DestinationName = $objListbox.Rows[$i].Cells[4].Value
    
          $renameInfos += $renameInfo
        }
      
        for ( $j = 0; $j -lt $objDnsbox.RowCount; $j ++ )
        {
          $DnsResource = $renameInfos | Where-Object { ($_.ResourceType -eq "publicIPAddresses") -and ( $_.SourceResourceGroup -eq  $objDnsbox.Rows[$j].Cells[1].Value) -and ($_.SourceName -eq  $objDnsbox.Rows[$j].Cells[2].Value) }
          $DnsResource.DnsName = $objDnsbox.Rows[$j].Cells[4].Value
        }

        $objForm.Dispose()
      }
      else
      {
        $objForm.Dispose()
        Break
      }

      return $renameInfos
    }
  }
  $job = Start-Job -InitializationScript $RenameFunction -ScriptBlock {Rename -vmResources $args} -ArgumentList $Script:vmResources
  $result = $job | Receive-Job -Wait -AutoRemoveJob
  $resultValidate = $false

  While (!$resultValidate)
  {
    $resultValidate = $True

    foreach ( $r in $result )
    {
      if ($r.ResourceType -ne "storageAccounts")
      {
        $resultCheck = $result | Where-Object { ($_.ResourceType -eq $r.ResourceType ) -and ( $_.DestinationResourceGroup -eq $r.DestinationResourceGroup ) -and ( $_.DestinationName -eq $r.DestinationName ) }
        if ( $resultCheck.Count -gt 1 )
        {
          Write-Warning ("Name Duplicate: (" + $r.ResourceType + ") Destination Name: " + $r.DestinationName + " Desitnation Resource Group: " + $r.DestinationResourceGroup + " . Please input the destination information again.")
          $resultValidate = $false
        }
      }
    }
    if (!$resultValidate)
    {
      $job = Start-Job -InitializationScript $RenameFunction -ScriptBlock {Rename -vmResources $args} -ArgumentList $Script:vmResources
      $result = $job | Receive-Job -Wait -AutoRemoveJob
    }
  }

  $renameInfos = @()
  $result | ForEach { 
    $renameInfo = New-Object ResourceProfile
    $renameInfo.ResourceType = $_.ResourceType
    $renameInfo.SourceResourceGroup = $_.SourceResourceGroup
    $renameInfo.DestinationResourceGroup = $_.DestinationResourceGroup
    $renameInfo.SourceName = $_.SourceName
    $renameInfo.DestinationName = $_.DestinationName
    $renameInfo.DnsName = $_.DnsName
    
    $renameInfos += $renameInfo
    }
  return $renameInfos

}

function Start-AzureRmVMMigration
{
  Param(
    [Parameter(Mandatory=$false)]
    [PSObject] $vm,

    [Parameter(Mandatory=$false)]
    [String] $destEnvironment,
  
    [Parameter(Mandatory=$false)]
    [String] $targetLocation,

    [Parameter(Mandatory=$false)]
    [PSObject] $SrcContext,

    [Parameter(Mandatory=$false)]
    [PSObject] $DestContext,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Validate", "Prepare", "VhdCopy", "VMBuild", "Rename", "All")]
    [String] $JobType = "All",

    [Parameter(Mandatory=$false)]
    [Object[]]
    $RenameInfos, 

    [Parameter(Mandatory=$false)]
    [String] $osDiskUri,

    [Parameter(Mandatory=$false)]
    [String[]] $dataDiskUris
  )

  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "-vm : parameter type is invalid. Please enter the right parameter type." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-SrcContext : parameter type is invalid. Please enter the right parameter type."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "-DestContext : parameter type is invalid. Please enter the right parameter type."
    }
  }
  
  if ($RenameInfos.Count -ne 0)
  {
    ForEach( $RenameInfo in $RenameInfos )
    {
      if ( $RenameInfo.GetType().FullName -notmatch "ResourceProfile" )
      {
        Throw "-RenameInfos : parameter type is invalid. Please enter the right parameter type: ResourceProfile"
      }
    }
  }

  ##PS Module Check
  Check-AzureRmMigrationPSRequirement

  #Define Azure Environment
  Enum AzureEnvironment
  {
    AzureCloud = 0
    AzureChinaCloud = 1
    AzureGermanCloud = 2
    AzureUSGovernment = 3
  }

  ##Form for GUI input
  $showFormCode = {
    Function Show-Form
    {
      Param(
        [Parameter(Mandatory=$True)]
        [String] $title,

        [Parameter(Mandatory=$True)]
        [String[]] $options,

        [Switch]
        $MultipleChoice
      )
      Add-Type -AssemblyName System.Windows.Forms
      Add-Type -AssemblyName System.Drawing

      $objForm = New-Object System.Windows.Forms.Form 
      $objForm.Text = "Azure Global Connection Center"
      $objForm.Size = New-Object System.Drawing.Size(700,500) 
      $objForm.StartPosition = "CenterScreen"

      $objForm.KeyPreview = $True

      $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
          {
            $objForm.DialogResult = "OK"
            $objForm.Close()
          }
      })

      $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
      {$objForm.Close()}})

      $objForm.BackColor = "#1F4E79"

      $Buttonfont = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Bold)
      $OKButton = New-Object System.Windows.Forms.Button
      $OKButton.Location = New-Object System.Drawing.Size(10,400)
      $OKButton.Size = New-Object System.Drawing.Size(180,40)
      $OKButton.Text = "OK"
      $OKButton.Font = $Buttonfont
      $OKButton.BackColor = "Gainsboro"

      $OKButton.Add_Click(
        {    
          $objForm.DialogResult = "OK"
          $objForm.Close()
      })

      $objForm.Controls.Add($OKButton)

      $CancelButton = New-Object System.Windows.Forms.Button
      $CancelButton.Location = New-Object System.Drawing.Size(200,400)
      $CancelButton.Size = New-Object System.Drawing.Size(180,40)
      $CancelButton.Text = "Cancel"
      $CancelButton.Font = $Buttonfont
      $CancelButton.BackColor = "Gainsboro"

      $CancelButton.Add_Click({$objForm.Close()})
      $objForm.Controls.Add($CancelButton)

      $objFont = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Italic)
      $objLabel = New-Object System.Windows.Forms.Label
      $objLabel.Location = New-Object System.Drawing.Size(10,20) 
      $objLabel.AutoSize = $True
      $objLabel.BackColor = "Transparent"
      $objLabel.ForeColor = "White"
      $objLabel.Font = $objFont
      $objLabel.Text = $title
      $objForm.Controls.Add($objLabel) 

      $objListbox = New-Object System.Windows.Forms.Listbox 
      $objListbox.Location = New-Object System.Drawing.Size(10,70) 
      $objListbox.Size = New-Object System.Drawing.Size(650,30) 

      if($MultipleChoice)
      {
        $objListbox.SelectionMode = "MultiExtended"
      }

      foreach ( $option in $options ) {
        [void] $objListbox.Items.Add($option)
      }

      $objlistfont = New-Object System.Drawing.Font("Arial",14,[System.Drawing.FontStyle]::Regular)
      $objListbox.Font = $objlistfont
      $objListbox.Height = 320
      $objForm.Controls.Add($objListbox) 


      $objForm.Add_Shown({$objForm.Activate()})
      [void] $objForm.ShowDialog()
      if ( $objForm.DialogResult -eq "OK" ) {

        $responses = @()
        foreach ( $selection in $objListbox.SelectedItems ) {
          $responses+= $selection
        }

        $objForm.Dispose()

      }

      if ($responses.Count -eq 0)
      {
        $objForm.Dispose()
        Break
      }

      return $responses
    }
  }

  Function SelectionBox
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $title,

      [Parameter(Mandatory=$True)]
      [String[]] $options,

      [Switch]
      $MultipleChoice
    )
    if($MultipleChoice){
        $job = Start-Job -InitializationScript $showFormCode -ScriptBlock {Show-Form -title $args[0] -options $args[1] -MultipleChoice} -ArgumentList $title,$options
    }
    else {
        $job = Start-Job -InitializationScript $showFormCode -ScriptBlock {Show-Form -title $args[0] -options $args[1]} -ArgumentList $title,$options
    }
    $result = $job | Receive-Job -Wait -AutoRemoveJob
    return $result
  }

  $Script:JobId = New-Guid | %{ $_.Guid }
  $Script:timeSpanList = @()

  ##Get the parameter if not provided
  Try
  {
    if ( $SrcContext -eq $null )
    {
      $SrcEnv = SelectionBox -title "Please Select the Source Environment" -options ("Microsoft Azure", "Microsoft Azure in Germany", "Azure in China (operated by 21 vianet)")
      Switch ( $SrcEnv )
      {
        "Azure in China (operated by 21 vianet)" { $SrcEnvironment = [AzureEnvironment] "AzureChinaCloud" }
        "Microsoft Azure in Germany" { $SrcEnvironment = [AzureEnvironment] "AzureGermanCloud" }
        "Microsoft Azure" { $SrcEnvironment = [AzureEnvironment] "AzureCloud" }
      }

      [Windows.Forms.MessageBox]::Show("Please Enter " + $SrcEnv + " credential after click OK", "Azure Global Connection Center", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      Add-AzureRmAccount -EnvironmentName $SrcEnvironment | Out-Null

      $subscriptions = Get-AzureRmSubscription
      $subList = @()

      ForEach ( $sub in $subscriptions )
      {
        $subList += $sub.SubscriptionName
      }

      $subscription = SelectionBox -title "Please Select the Source Subscription" -options $subList

      Select-AzureRmSubscription -SubscriptionName $Subscription | Out-Null

      $SrcContext = Get-AzureRmContext
    }

    MigrationTelemetry -srcContext $srcContext

    if ($destContext -eq $null )
    {
      if ([string]::IsNullOrEmpty($destEnvironment))
      {
        $destEnv = SelectionBox -title "Please Select the Destination Environment" -options ("Azure in China (operated by 21 vianet)", "Microsoft Azure in Germany", "Microsoft Azure")
        Switch ( $destEnv )
        {
          "Azure in China (operated by 21 vianet)" { $destEnvironment = [AzureEnvironment] "AzureChinaCloud" }
          "Microsoft Azure in Germany" { $destEnvironment = [AzureEnvironment] "AzureGermanCloud" }
          "Microsoft Azure" { $destEnvironment = [AzureEnvironment] "AzureCloud" }
        }
      }
      else
      {
        $destEnvironment = [AzureEnvironment] $destEnvironment
      }

      [Windows.Forms.MessageBox]::Show("Please Enter " + $destEnv + " credential after click OK", "Azure Global Connection Center", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      Add-AzureRmAccount -EnvironmentName $destEnvironment | Out-Null

      $subscriptions = Get-AzureRmSubscription
      $subList = @()

      ForEach ( $sub in $subscriptions )
      {
        $subList += $sub.SubscriptionName
      }

      $subscription = SelectionBox -title "Please Select the Desitnation Subscription" -options $subList

      Select-AzureRmSubscription -SubscriptionName $Subscription | Out-Null

      $destContext = Get-AzureRmContext
    }

    if ( $vm -eq $null )
    {
      Set-AzureRmContext -Context $SrcContext | Out-Null

      $vms = Get-AzureRmVM
      $vmList = @()

      ForEach ( $v in $vms )
      {
        $vmDescription = $v.Name + "(Resource Group:" + $v.ResourceGroupName +")"
        $vmList += $vmDescription
      }

      $vmSelected = SelectionBox -title "Please Select the VM to Migrate" -options $vmList

      $vmName = $vmSelected.Split("(")[0]
      $vmResourceGroupName = $vmSelected.Split(":")[1].Replace(")","")

      $vm = Get-AzureRmVM -ResourceGroupName $vmResourceGroupName -Name $vmName
  
    }


    if ([string]::IsNullOrEmpty($targetLocation))
    {
      Set-AzureRmContext -Context $DestContext | Out-Null
  
      $locations = Get-AzureRmLocation
      $locationList = @()

      ForEach ( $loc in $locations )
      {
        $locationList += $loc.DisplayName
      }

      $Location = SelectionBox -title "Please Select the Destination Location" -options $locationList
      $targetLocation = ($locations | Where-Object { $_.DisplayName -eq $Location }).Location
    }
    else
    {
      Set-AzureRmContext -Context $DestContext | Out-Null
  
      $locations = Get-AzureRmLocation

      $locationCheck = $locations | Where-Object { ($_.DisplayName -eq $targetLocation) -or ( $_.Location -eq $targetLocation ) }

      if ( $locationCheck -eq $null )
      {
        Throw ( "The targetLocation " + $targetLocation + " is invalid." )
      }

      $targetLocation = $locationCheck.Location
    }
    
    if ($RenameInfos -eq $null)
    {
      $RenameInfos = Set-AzureRmVMMigrationRename -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext
    }
    MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "UserInput" -phaseStatus Succeed
  }
  Catch
  {
    Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
    MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "UserInput" -phaseStatus Failed -completed
    Throw "Input Parameters are not set correctly. Please try again."
  }




  Switch($JobType)
  {
    ##Validation Only
    "Validate"
    {
      Try
      {
        $validationResult = Start-AzureRmVMMigrationValidate -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
      }
      Catch
      {
        Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
        MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Failed
        Throw "Validation Failed. Please check the error message and try again."
      }
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Succeed
      return $validationResult
    }

    ##Prepare Only
    "Prepare"
    {
      Try
      {
        Start-AzureRmVMMigrationPrepare -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -RenameInfos $RenameInfos
      }
      Catch
      {
        Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
        MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "Preparation" -completed -phaseStatus Failed
        Throw "Preparation Failed. Please check the error message and try again."
      }
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "Preparation" -completed -phaseStatus Succeed
      return
    }

    ##VHD Copy Only
    "VhdCopy"
    {
      Try
      { 
        $diskUris,$vm = Start-AzureRmVMMigrationVhdCopy -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -RenameInfos $RenameInfos
      }
      Catch
      {
        Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
        MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VhdCopy" -completed -phaseStatus Failed
        Throw "Vhd Copy Failed. Please check the error message and try again."
      }
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VhdCopy" -completed -phaseStatus Succeed
      return $diskUris
    }

    ##VMBuild Only
    "VMBuild"
    {
      if([String]::IsNullOrEmpty($osDiskUri) )
      {
        Throw ( "-osDiskUri Parameter is null or empty. Please input correct value." )
      }
    
      Try
      {
        Start-AzureRmVMMigrationBuild -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -osDiskUri $osDiskUri -dataDiskUris $dataDiskUris -RenameInfos $RenameInfos
      }
      Catch
      {
        Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
        MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VMBuild" -completed -phaseStatus Failed
        Throw "VM Building Failed. Please check the error message and try again."
      } 
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VMBuild" -completed -phaseStatus Succeed
      return
    }
    
    #Rename Only
    "Rename"
    {
      Try
      {
        $RenameInfos = Set-AzureRmVMMigrationRename -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext
      }
      Catch
      {
        Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
        Throw "Rename Failed. Please check the error message and try again."
      }
      return $RenameInfos
    }
  }

  ##Confirm and Deploy
  $migrationConfirmation = [System.Windows.Forms.MessageBox]::Show("Migrate virtual machine: " + $vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")?" , "Azure Global Connection Center" , 4)

  if ($migrationConfirmation -eq "Yes")
  {
    Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Migration Started" -percentComplete 0

    Try
    {
      $validationResult = Start-AzureRmVMMigrationValidate -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos    
    }
    Catch
    {
      Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Failed
      Throw "Validation Failed. Please check the error message and try again."
    }
    
    if ($validationResult.Result -eq "Failed")
    {
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Failed
      return $validationResult
    }
    else
    {
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -phaseStatus Succeed
    }
  
    Try
    {
      Start-AzureRmVMMigrationPrepare -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -RenameInfos $RenameInfos
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "Preparation" -phaseStatus Succeed
    }
    Catch
    {
      Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "Preparation" -completed -phaseStatus Failed
      Throw "Preparation Failed. Please check the error message and try again."
    }
    
    Try
    {
      $diskUris,$vm = Start-AzureRmVMMigrationVhdCopy -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -RenameInfos $RenameInfos
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VhdCopy" -phaseStatus Succeed
    }
    Catch
    {
      Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VhdCopy" -completed -phaseStatus Failed
      Throw "Vhd Copy Failed. Please check the error message and try again."
    }
    
    Try
    {
      Start-AzureRmVMMigrationBuild -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -osDiskUri $diskUris.osDiskUri -dataDiskUris $diskUris.dataDiskUris -RenameInfos $RenameInfos
    }
    Catch
    {
      Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "VMBuild" -completed -phaseStatus Failed
      Throw "VM Building Failed. Please check the error message and try again."
    }
    Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Migration Succeeded" -percentComplete 100
  
    return ("VM: " + $vm.Name +  " Migration Succeeded.")
  }
  
}

Export-ModuleMember -Function Start-AzureRmVMMigration