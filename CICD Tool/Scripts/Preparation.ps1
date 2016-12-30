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

