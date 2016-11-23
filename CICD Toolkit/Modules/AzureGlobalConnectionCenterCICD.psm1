Function Check-AzureRmMigrationPSRequirement
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

    if ( ($module.Version.Major -ge 2) -or (($module.Version.Major -eq 1) -and ( $module.Version.Minor -ge 7 ) ) )
    { break }
    else
    { Throw "This script requires AzureRm PowerShell version higher than 1.7.0. Please install the latest Azure Powershell before execute this script." }
    
  }

  Check-AzurePSModule -module $AzureRmStorage
  Check-AzurePSModule -module $AzureRmCompute
  Check-AzurePSModule -module $AzureRMNetwork
  Check-AzurePSModule -module $AzureRMProfile

}

function Start-AzureRmVMMigrationValidate
{
  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] 
    $vm,

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

  ##PS Module Check
  Check-AzureRmMigrationPSRequirement

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
    $resource.SourceResourceGroup = $resourceId.Split("/")[4]
   
    $resourceCheck = $vmResources | Where-Object { $_ -eq $resource }
   
    if ( $resourceCheck -eq $null )
    {
      $Script:vmResources += $resource
    }
  }

  Function Add-StorageList
  {
    Param(
      [Parameter(Mandatory=$True)]
      [String] $storName   
    )

    $storCheck = $vmResources | Where-Object { ($_.Name -eq $storName) -and ($_.ResourceType -eq "storageAccounts" ) }

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
  $vmResources = @()

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
    if ( $osuri -match "https" ) {
    $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
    else {
      $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
    }
    Add-StorageList -storName $datastorname
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
            $messageHeader = "[Error]"
        }
        "SucceedWithWarning"{
            if($Script:result -eq "Succeed"){
                $Script:result = "SucceedWithWarning"
            }
            $messageHeader = "[Warning]"
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
  $result = "Succeed"
  $resultDetailsList = @()

  # check src permission
  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Checking Permission" -percentComplete 10

  Set-AzureRmContext -Context $SrcContext | Out-Null
  $roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $SrcContext.Account

  if(!($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner")) 
  {
    Add-ResultList -result "Failed" -detail "The current user don't have source subscription permission, because the user is not owner or coAdmin."
  }


  # check dest permission
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


  # Storage Quota Check
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
       $saCheck = $storageAccountNames | Where-Object { $_ -eq $resource.SourceName }
       if ( $saCheck -eq $null )
       {
           $storageAccountNames += $resource.SourceName
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
    if($resource.ResourceType -eq "publicIPAddresses"){
        Set-AzureRmContext -Context $SrcContext | Out-Null
        $sourcePublicAddress = Get-AzureRmPublicIpAddress -Name $resource.SourceName -ResourceGroupName $resource.SourceResourceGroup
        Set-AzureRmContext -Context $DestContext | Out-Null
        if($sourcePublicAddress.DnsSettings.DomainNameLabel -ne $null)
        {
            $dnsTestResult = Test-AzureRmDnsAvailability -DomainNameLabel $sourcePublicAddress.DnsSettings.DomainNameLabel -Location $targetLocation
            if($dnsTestResult -ne "True")
            {
                Add-ResultList -result "Failed" -detail ("The dns name " + $sourcePublicAddress.DnsSettings.DomainNameLabel + " validate failed, because DNS name not available in target location.")
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
                                      Where-Object {$_.ResourceId.Split("/")[4] -eq $resource.SourceResourceGroup} | 
                                      Where-Object {$_.Name -eq $resource.SourceName}
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
        Add-ResultList -result $resourceResult -detail ("The resource:" + $resource.SourceName +  " (type: "+$resource.ResourceType+") in Resource Group: " + $resource.SourceResourceGroup + " already exists in destination.")
    }
    


  }

  Write-Progress -id 40 -parentId 0 -activity "Validation" -status "Complete" -percentComplete 100

  $validationResult = New-Object PSObject
  $validationResult | Add-Member -MemberType NoteProperty -Name ValidationResult -Value $result
  $validationResult | Add-Member -MemberType NoteProperty -Name Messages -Value $resultDetailsList

  return $validationResult

}

function Start-AzureRmVMMigrationPrepare
{
  Param(
    [Parameter(Mandatory=$True)]
    [PSObject] 
    $vm,

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

  ##PS Module Check
  Check-AzureRmMigrationPSRequirement

  ####Write Progress####

  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Preparing Migration" -percentComplete 5
  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Started" -percentComplete 0

  ####Collecting VM Information####

  Set-AzureRmContext -Context $SrcContext | Out-Null

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
      $targetRg.Location = $script:targetLocation

      $Script:resourceGroups += $targetRg
    }

  }


  #Get Dependencies
  Write-Progress -id 10 -parentId 0 -activity "Preparation" -status "Getting Dependencies" -percentComplete 15

  ##Handle Resource Group Dependencies: List Distinct Resource Group
  #VM
  $resourceGroups = @()

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
  $storageAccounts = @()

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
    if ( $osuri -match "https" ) {
    $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
    else {
      $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
    }
    Add-StorageList -storName $datastorname
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
    [Parameter(Mandatory=$True)]
    [PSObject] 
    $vm,

    [Parameter(Mandatory=$True)]
    [String] 
    $targetLocation,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $SrcContext,

    [Parameter(Mandatory=$true)]
    [PSObject] 
    $DestContext
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

  ##PS Module Check
  Check-AzureRmMigrationPSRequirement

  #Storage Infomation Define
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
  Set-AzureRmContext -Context $DestContext | Out-Null
  $osDiskInfo.DestAccountName = $osDiskInfo.SrcAccountName
  $osDiskInfo.DestBlobName = $osDiskInfo.SrcBlobName
  $osDiskInfo.DestContainerName = $osDiskInfo.SrcContainerName

  $osStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $osDiskInfo.DestAccountName }
  $osDiskInfo.DestAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $osStorAccount.ResourceGroupName -Name $osStorAccount.StorageAccountName)[0].Value

  $StorageInfos += $osDiskInfo


  #DataDisk
  foreach($dataDisk in $vm.StorageProfile.DataDisks)
  {
    $dataDiskInfo = New-Object StorageInfo
    $dataDiskInfo.Lun = $dataDisk.Lun
   
    Set-AzureRmContext -Context $SrcContext | Out-Null
    $datauri = $dataDisk.Vhd.Uri
    if ( $osuri -match 'https' ) {
    $dataDiskInfo.SrcAccountName = $datauri.Substring(8, $datauri.IndexOf('.blob') - 8)}
    else {
      $dataDiskInfo.SrcAccountName = $datauri.Substring(7, $datauri.IndexOf('.blob') - 7)
    }
    $dataDiskInfo.SrcContainerName = $datauri.Split('/')[3]
    $dataDiskInfo.SrcBlobName = $datauri.Split('/')[$datauri.Split('/').Count - 1]

    $dataStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $dataDiskInfo.SrcAccountName }
    $dataDiskInfo.SrcAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $dataStorAccount.ResourceGroupName -Name $dataStorAccount.StorageAccountName)[0].Value

    #Destination Storage Information
    Set-AzureRmContext -Context $DestContext | Out-Null
    $dataDiskInfo.DestAccountName = $dataDiskInfo.SrcAccountName
    $dataDiskInfo.DestBlobName = $dataDiskInfo.SrcBlobName
    $dataDiskInfo.DestContainerName = $dataDiskInfo.SrcContainerName

    $dataStorAccount = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $dataDiskInfo.DestAccountName }
    $dataDiskInfo.DestAccountSecret = (Get-AzureRmStorageAccountKey -ResourceGroupName $dataStorAccount.ResourceGroupName -Name $dataStorAccount.StorageAccountName)[0].Value

    $StorageInfos += $dataDiskInfo
  }


  ####Start Vhds Copy####

  Foreach ( $vhd in $StorageInfos )
  {
    $srcStorageContext = New-AzureStorageContext -StorageAccountName $vhd.SrcAccountName -StorageAccountKey $vhd.SrcAccountSecret -Environment $SrcContext.Environment
    $destStorageContext = New-AzureStorageContext -StorageAccountName $vhd.DestAccountName -StorageAccountKey $vhd.DestAccountSecret -Environment $DestContext.Environment

    $srcBlob = Get-AzureStorageBlob -Blob $vhd.SrcBlobName -Container $vhd.SrcContainerName -Context $srcStorageContext

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

  return $diskUris
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
    $DestContext  

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

  ##PS Module Check
  Check-AzureRmMigrationPSRequirement

  Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Building VM" -percentComplete 70
  Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Started" -percentComplete 0

  Enum VMResourceType
  {
    virtualMachines = 1
    publicIPAddresses = 2
    networkInterfaces = 3
    virtualNetworks = 4
    networkSecurityGroups = 5
    availabilitySets = 6
    loadBalancers = 7
  }


  Class ResourceProfile
  {
    [String] $ResourceGroupName
    [String] $Name
    [VMResourceType] $ResouceType
  }


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
    $resource.Name = $resourceId.Split("/")[8]
    $resource.ResouceType = $resourceId.Split("/")[7]
    $resource.ResourceGroupName = $resourceId.Split("/")[4]
   
    $resourceCheck = $vmResources | Where-Object { $_ -eq $resource }
   
    if ( $resourceCheck -eq $null )
    {
      $Script:vmResources += $resource
    }
    
  }

  ####Get VM Components####
  Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Getting VM Components" -percentComplete 10

  ##Handle Resource Group Dependencies: List Distinct Resource Group

  Set-AzureRmContext -Context $SrcContext | Out-Null
  #VM
  $resourceGroups = @()
  $vmResources = @()

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


  ####Get ARM Template and Modify####
  $resourcelist = New-Object PSObject
  $tempId = [guid]::NewGuid()

  Foreach ( $rg in $resourceGroups ) {
    #Get the Target Resource Group ARM Template
    $Sourcetemplatefolder = New-Item -ItemType directory -Path "$Env:TEMP\AzureMigrationtool" -Force
    $Sourcetemplatepath = $Env:TEMP + "\AzureMigrationtool\$tempId" + "\Source" + $rg + ".json"

    Export-AzureRmResourceGroup -ResourceGroupName $rg -Path $Sourcetemplatepath -IncludeParameterDefaultValue -Force -WarningAction Ignore | Out-Null

    $sourcetemplate = Get-Content -raw -Path $Sourcetemplatepath | ConvertFrom-Json

    $targetresources = New-Object PSObject
    $container = @()
    $targetresources | Add-Member -Name 'Phase1' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase2' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase3' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase4' -MemberType NoteProperty -Value $container
    $targetresources | Add-Member -Name 'Phase5' -MemberType NoteProperty -Value $container

    $resourcecont = New-Object PSObject

    $resourcecont | Add-Member -Name 'sourcetemplate' -MemberType NoteProperty -Value $sourcetemplate
    $resourcecont | Add-Member -Name 'targetresources' -MemberType NoteProperty -Value $targetresources

    $resourcelist | Add-Member -Name $rg -MemberType NoteProperty -Value $resourcecont
  }


  #Classify and Modify ARM Template
  ForEach ( $resource in $vmResources )
  {
    $name = ("_" + $resource.Name + "_").Replace("-","_")
  
    switch ($resource.ResouceType)
    {
      { $_ -in "publicIPAddresses", "networkSecurityGroups", "availabilitySets" } { $phase = 'Phase1' }
      'virtualNetworks' { $phase = 'Phase2' }
      'loadBalancers' { $phase = 'Phase3' }
      'networkInterfaces' { $phase = 'Phase4' }
      'virtualMachines' { $phase = 'Phase5' }
    }
  
    $resourcecheck = $resourcelist.$rg.targetresources.$phase | Where-Object { ($_.name -match $name) -and ($_.type -match $resource.ResouceType) }
  
    if ( $resourcecheck -eq $null ) {

      if ($resource.ResouceType -eq 'virtualMachines')
      {
        $c = $resourcelist.$rg.sourcetemplate.resources | Where-Object { ($_.name -match $name) -and ($_.type -eq "Microsoft.Compute/virtualMachines") }

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

        $crsdeps = @()
        Foreach ( $cdep in $c.dependsOn ) {
          if ( $cdep -notmatch "Microsoft.Storage/storageAccounts" ) {
            $crsdeps += $cdep
          }
        }

        $crs = New-Object PSObject
        $crs | Add-Member -Name "type" -MemberType NoteProperty -Value $c.type
        $crs | Add-Member -Name "name" -MemberType NoteProperty -Value $c.name
        $crs | Add-Member -Name "apiVersion" -MemberType NoteProperty -Value $c.apiVersion
        $crs | Add-Member -Name "location" -MemberType NoteProperty -Value $targetLocation
        $crs | Add-Member -Name "tags" -MemberType NoteProperty -Value $c.tags
        $crs | Add-Member -Name "properties" -MemberType NoteProperty -Value $crsprop
        $crs | Add-Member -Name "dependsOn" -MemberType NoteProperty -Value $crsdeps

        $resourcelist.$rg.targetresources.Phase5 += $crs
      }
      else
      {
        $targetresource = $resourcelist.$rg.sourcetemplate.resources | Where-Object { ($_.name -match $name) -and ($_.type -match $resource.ResouceType) }
        $targetresource.location = $targetLocation
        $resourcelist.$rg.targetresources.$phase += $targetresource
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
  }

  $progressPercentage = 40

  #VM Deploy by Phase
  For($i = 1; $i -le 5 ; $i++ )
  {
    $currentPhase = "Phase" + $i

    Foreach ( $rg in $resourceGroups ) {
    
      if ( $resourcelist.$rg.targetresources.$currentPhase.Count -ne 0 ){

        $SourceResourceGroupName = $rg
        $TargetResourceGroupName = $rg

        $sourcetemplate = $resourcelist.$rg.sourcetemplate
    
        #Set Target ARM Template with source settings
        $targettemplate = New-Object PSObject
        $targettemplate | Add-Member -Name '$schema' -MemberType NoteProperty -Value $sourcetemplate.'$schema'
        $targettemplate | Add-Member -Name "contentVersion" -MemberType Noteproperty -Value $sourcetemplate.contentVersion
        $targettemplate | Add-Member -Name "parameters" -MemberType Noteproperty -Value $null
        $targettemplate | Add-Member -Name "variables" -MemberType Noteproperty -Value $sourcetemplate.variables
        $targettemplate | Add-Member -Name "resources" -MemberType Noteproperty -Value $null

      
        $targettemplate.resources = $resourcelist.$rg.targetresources.Phase1

        for ( $j = 2; $j -le $i; $j ++ )
        {
          $addPhase = "Phase" + $j
          $targettemplate.resources += $resourcelist.$rg.targetresources.$addPhase
        }
      
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
          
            $resourceChecks += $resourceCheck 
          }
        
        
          While ( $resourceChecks.Count -ne 0 )
          {
            $newResourceMembers = @()
            ForEach ( $resourceCheck in $resourceChecks )
            {
              ForEach ( $parent in $resourcecheck.Parent )
              {
                $value = $parent.($resourceCheck.Name)
              
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
                          $resourceCheck.Parent = $value
          
                          $newResourceMembers += $resourceCheck
                        }
                      }
                    }
                    Default
                    {
                      if ( $value -match "\[parameters\('" )
                      {
                        $parameterList += $value.Split("'")[1]
                      }
                    }
                  } 
                }
              }
            }
          
            $resourceChecks = $newResourceMembers
          
          }
        }
        $parameterList = $parameterList | Select-Object -Unique

        $targetparameters = $sourcetemplate.parameters | Select-Object -Property $parameterList
        $targetparpmembers = $targetparameters | Get-Member -MemberType NoteProperty
        Foreach ( $tm in $targetparpmembers ) {
          $tmname = $tm.Name
          if (($targetparameters.$tmname.defaultValue -ne $null) -and ( $targetparameters.$tmname.type -eq "String" ) ) {
            $targetparameters.$tmname.defaultValue = $targetparameters.$tmname.defaultValue.Replace("/subscriptions/$SourceSubID","/subscriptions/$DestSubID")
            $targetparameters.$tmname.defaultValue = $targetparameters.$tmname.defaultValue.Replace("/resourceGroups/$SourceResourceGroupName","/resourceGroups/$TargetResourceGroupName")   
          }
          if ( ($tmname -match "primary") -and ( $targetparameters.$tmname.type -eq "Bool" ) ) {
            $targetparameters.$tmname.defaultValue = $True
          }
        }

        $targettemplate.parameters = $targetparameters
      
        $targettemplatename = "Target" + $rg + $currentPhase + ".json"
      
        $targetjson = $targettemplate | ConvertTo-Json -Depth 9
        $targettemplatepath = $Env:TEMP + "\AzureMigrationtool\$tempId" + "\" + $targettemplatename
        $targetjson -replace "\\u0027", "'" | Out-File $targettemplatepath
      
     
        New-AzureRmResourceGroupDeployment -ResourceGroupName $rg -TemplateFile $targettemplatepath | Out-Null    

      }
    }

    $progressPercentage += 10

    Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Deploying VM" -percentComplete $progressPercentage
  }


  ####Validate the VM Deployment####
  Write-Progress -id 30 -ParentId 0 -activity "Building VM" -status "Validating deployment" -percentComplete 95

  $destVM = Get-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name

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

    Throw "The VM Migration is Failed."
  }


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

    [switch] $validate
  )

  ##Parameter Type Check
  if ( $vm -ne $null )
  {
    if ( $vm.GetType().FullName -ne "Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine" )
    {
      Throw "`$vm : parameter type is invalid. Please enter the right parameter type." 
    }
  }

  if ( $SrcContext -ne $null )
  {
    if ( $SrcContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "`$SrcContext : parameter type is invalid. Please enter the right parameter type."
    }
  }

  if ( $DestContext -ne $null )
  {
    if ( $DestContext.GetType().FullName -ne "Microsoft.Azure.Commands.Profile.Models.PSAzureContext" )
    {
      Throw "`$DestContext : parameter type is invalid. Please enter the right parameter type."
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
  
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 

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

    }

    if ($responses.Count -eq 0)
    {
      Break
    }

    return $responses
  }

  ##Get the parameter if not provided

  if ( $SrcContext -eq $null )
  {
    $SrcEnv = SelectionBox -title "Please Select the Source Environment" -options ("Global Azure", "Germany Azure", "China Azure")
    Switch ( $SrcEnv )
    {
      "China Azure" { $SrcEnvironment = [AzureEnvironment] "AzureChinaCloud" }
      "Germany Azure" { $SrcEnvironment = [AzureEnvironment] "AzureGermanCloud" }
      "Global Azure" { $SrcEnvironment = [AzureEnvironment] "AzureCloud" }
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


  if ($destContext -eq $null )
  {
    if ([string]::IsNullOrEmpty($destEnvironment))
    {
      $destEnv = SelectionBox -title "Please Select the Destination Environment" -options ("China Azure", "Germany Azure", "Global Azure")
      Switch ( $destEnv )
      {
        "China Azure" { $destEnvironment = [AzureEnvironment] "AzureChinaCloud" }
        "Germany Azure" { $destEnvironment = [AzureEnvironment] "AzureGermanCloud" }
        "Global Azure" { $destEnvironment = [AzureEnvironment] "AzureCloud" }
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

  ##Validation Only
  if ($validate)
  {
    $validationResult = Start-AzureRmVMMigrationValidate -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext
    return $validationResult
  }


  ##Confirm and Deploy
  $migrationConfirmation = [System.Windows.Forms.MessageBox]::Show("Migrate virtual machine: " + $vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")?" , "Azure Global Connection Center" , 4)

  if ($migrationConfirmation -eq "Yes")
  {
    Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Migration Started" -percentComplete 0

    $validationResult = Start-AzureRmVMMigrationValidate -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext

    if ($validationResult.Result -eq "Failed")
    {
      return $validationResult
    }
  
    Start-AzureRmVMMigrationPrepare -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext

    $diskUris = Start-AzureRmVMMigrationVhdCopy -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext

    Start-AzureRmVMMigrationBuild -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $destContext -osDiskUri $diskUris.osDiskUri -dataDiskUris $diskUris.dataDiskUris

    Write-Progress -id 0 -activity ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" ) -status "Migration Succeeded" -percentComplete 100
  
    return ($vm.Name + "(ResourceGroup:" + $vm.ResourceGroupName + ")" + "Migration Succeeded")
  }

}

Export-ModuleMember -Function Start-AzureRmVMMigration, Start-AzureRmVMMigrationValidate, Start-AzureRmVMMigrationPrepare, Start-AzureRmVMMigrationVhdCopy, Start-AzureRmVMMigrationBuild