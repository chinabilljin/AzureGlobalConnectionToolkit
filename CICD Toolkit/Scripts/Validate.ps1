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
#$targetLocation = "chinaeast"
#Add-AzureRmAccount -EnvironmentName AzureChinaClouds
#$vm = Get-azurermvm -ResourceGroupName CATDEMORG -name catmawebSrv0

#$destContext = Get-AzureRmContext

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



#####################################
Function Add-ResultList
{
   Param(
   [Parameter(Mandatory=$True)]
   [String] $result
   )   
   $Script:resultList += $result
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


$resultList = @()
#return success or not, reason

# check src permission
$roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $SrcContext.Account

if($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner") {
    Add-ResultList -result "The current user have source subscription permission"
}
else {
    Add-ResultList -result "The current user don't have source subscription permission, because the user is not owner or coAdmin"
}


# check dest permission
$roleAssignment = Get-AzureRmRoleAssignment -IncludeClassicAdministrators -SignInName $DestContext.Account

if($roleAssignment.RoleDefinitionName -eq "CoAdministrator" -or $roleAssignment.RoleDefinitionName -eq "Owner") {
    Add-ResultList -result "The current user have destination subscription permission"
}
else {
    Add-ResultList -result "The current user don't have destination subscription permission, because the user is not owner or coAdmin"
}


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
    Add-ResultList -result "The vm core quota validate failed, because Total Regional Cores over quota"
}
else{
    Add-ResultList -result "The vm core quota validate successful"
}
if($vmCoreNumber -gt $vmAvailableFamilyCoreUsage) {
    Add-ResultList -result "The vm core quota validate failed, because " + $vmCoreFamily + " over quota"
}
else{
    Add-ResultList -result "The vm core quota validate successful"
}

# Storage Quota Check

$storageUsage = Get-AzureRmStorageUsage
$storageAvailable = $storageUsage.Limit - $storageUsage.CurrentValue

if($storageAccounts.Count -gt $storageAvailable)
{
    Add-ResultList -result "The storage account validate failed, because over storage account quota"
}
else
{
    Add-ResultList -result "The storage account validate successful"
}

# RG Name Existence

Foreach ($rg in $resourceGroups)
{
    $rgCheck = Get-AzureRmResourceGroup -Name $rg.ResourceGroupName -ErrorAction Ignore


    if ($rgCheck -eq $null)
    {
        Add-ResultList -result "The resource group " + $rg.ResourceGroupName + " validate successful"
    }
    else
    {
        Add-ResultList -result "The resource group " + $rg.ResourceGroupName + " validate failed, because resource group name exist"
    }

}

# Storage Name Existence


Foreach ($storage in $storageAccounts)
{
  $storageCheck = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $storage.StorageAccountName}

  if ( $storageCheck -eq $null )
  {
     $storageAvailability = Get-AzureRmStorageAccountNameAvailability -Name $storage.StorageAccountName
     if ($storageAvailability.NameAvailable -eq $false)
     {
        Add-ResultList -result "The storage account " + $storage.StorageAccountName + " validate failed, because " + $storageAvailability.Reason
     }
  }

}

$resultList



# Resource Existence
