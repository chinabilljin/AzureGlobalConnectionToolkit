Param(
[Parameter(Mandatory=$True)]
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $vm,

[Parameter(Mandatory=$True)]
[String] $targetLocation,

[Parameter(Mandatory=$true)]
[Microsoft.Azure.Commands.Profile.Models.PSAzureContext] 
$SrcContext,

[Parameter(Mandatory=$true)]
[Microsoft.Azure.Commands.Profile.Models.PSAzureContext] 
$DestContext  

)


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


#####################################
Enum ResultType
{
   Failed = 0
   Success = 1
   SuccessWithWarning = 2
}

Function Add-ResultList
{
Param(
    [Parameter(Mandatory=$True)]
    [ResultType] $result,
    [Parameter(Mandatory=$False)]
    [String] $detail
    )
    switch($result){
        "Failed"{
            $Script:result = "Failed";
        }
        "SuccessWithWarning"{
            if($Script:result -eq "Success"){
                $Script:result = "SuccessWithWarning"
            }
        }
    }
    if($detail){
        $Script:resultDetailsList += $detail
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

$result = "Success"
$resultDetailsList = @()
#return success or not, reason

# check src permission
$roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $SrcContext.Account

if($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner") {
    Add-ResultList -result "Success"
}
else {
    Add-ResultList -result "Failed" -detail "The current user don't have source subscription permission, because the user is not owner or coAdmin"
}


# check dest permission
$roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $DestContext.Account

if($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner") {
    Add-ResultList -result "Success"
}
else {
    Add-ResultList -result "Failed" -detail "The current user don't have destination subscription permission, because the user is not owner or coAdmin"
}



#################################
Set-AzureRmContext -Context $DestContext | Out-Null
 
# Core Quota Check

$vmHardwareProfile = Get-AzureRmVmSize -Location $targetLocation | Where-Object{$_.Name -eq $vm.HardwareProfile.VmSize}
$vmCoreNumber = $vmHardwareProfile.NumberOfCores

$vmCoreFamily = Get-AzureRmVmCoreFamily -VmSize $vm.HardwareProfile.VmSize

$vmUsage = Get-AzureRmVMUsage -Location $targetLocation
$vmTotalCoreUsage = $vmUsage | Where-Object{$_.Name.LocalizedValue -eq "Total Regional Cores"}
$vmFamilyCoreUsage = $vmUsage | Where-Object{$_.Name.LocalizedValue -eq $vmCoreFamily}

$vmAvailableTotalCore = $vmTotalCoreUsage.Limit - $vmTotalCoreUsage.CurrentValue
$vmAvailableFamilyCoreUsage = $vmFamilyCoreUsage.Limit - $vmFamilyCoreUsage.CurrentValue

if($vmCoreNumber -gt $vmAvailableTotalCore) {
    $resultDetail = "The vm core quota validate failed, because Total Regional Cores over quota"
    Add-ResultList -result "Failed" -detail $resultDetail
}
else{
    Add-ResultList -result "Success"
}
if($vmCoreNumber -gt $vmAvailableFamilyCoreUsage) {
    $resultDetail = "The vm core quota validate failed, because " + $vmCoreFamily + " over quota"
    Add-ResultList -result "Failed" -detail $resultDetail
}
else{
    Add-ResultList -result "Success"
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
    $resultDetail = "The storage account quota validate failed, because over enough storage account available"
    Add-ResultList -result "Failed" -detail $resultDetail
}
else
{
    Add-ResultList -result "Success"
}



# Storage Name Existence

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
        $resultDetail = "The storage account " + $storage + " validate failed, because " + $storageAvailability.Reason
        Add-ResultList -result "Failed" -detail $resultDetail
     }
     else
     {
        Add-ResultList -result "Success"
     }
  }
  else
  {
        Add-ResultList -result "SuccessWithWarning" -detail "storage account name exist in the subscription"
  }
}

# DNS Name Check

foreach ( $resource in $vmResources)
{
   if($resource.ResourceType -eq "publicIPAddresses"){
        Set-AzureRmContext -Context $SrcContext | Out-Null
        $sourcePublicAddress = Get-AzureRmPublicIpAddress -Name $resource.SourceName -ResourceGroupName $resource.SourceResourceGroup
        Set-AzureRmContext -Context $DestContext | Out-Null
        if($sourcePublicAddress.DnsSettings.DomainNameLabel -ne $null)
        {
            $dnsTestResult = Test-AzureRmDnsAvailability -DomainNameLabel $sourcePublicAddress.DnsSettings.DomainNameLabel -Location $targetLocation
            if($dnsTestResult -eq "True")
            {
                Add-ResultList -result "Success"
            }
            else
            {
                $resultDetail = "The dns name " + $sourcePublicAddress.DnsSettings.DomainNameLabel + " validate failed, because DNS name not available in target location."
                Add-ResultList -result "Failed" -detail $resultDetail
            }
        }
   }
}

# Resource Existence
Set-AzureRmContext -Context $DestContext | Out-Null

$DestResources = Get-AzureRmResource 

foreach ( $resource in $vmResources)
{
    $resourceCheck = $DestResources | Where-Object {$_.ResourceType -match $resource.ResourceType } | 
                                      Where-Object {$_.ResourceId.Split("/")[4] -eq $resource.SourceResourceGroup} | 
                                      Where-Object {$_.Name -eq $resource.SourceName}
    if ($resourceCheck -eq $null)
    { 
        $resourceResult = "Sucess"
    }
    else
    {
        switch ($resource.ResourceType) 
        { 
            "virtualMachines" {$resourceResult = "Failed"} 
            "availabilitySets" {$resourceResult = "Failed"}
            "networkInterfaces" {$resourceResult = "Failed"}
            "loadBalancers" {$resourceResult = "SuccessWithWarning"}
            "publicIPAddresses" {$resourceResult = "SuccessWithWarning"}
            "virtualNetworks" {$resourceResult = "SuccessWithWarning"}
            "networkSecurityGroups" {$resourceResult = "SuccessWithWarning"}
            "storageAccounts" {$resourceResult = "SuccessWithWarning"}
        }
        $resultDetail = "The resource type "+$resource.ResourceType+", name " + $resource.SourceName + " validate not successful, because resource name exist"
    }
    Add-ResultList -result $resourceResult -detail $resultDetail


}

$result
$resultDetailsList