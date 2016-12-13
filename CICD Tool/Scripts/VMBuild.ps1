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
    if ( $RenameInfo.GetType().FullName -ne "ResourceProfile" )
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
   
    $resourceCheck = $vmResources | Where-Object { $_ -eq $resource }
   
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

$sourceParameters = @()

$tempId = [guid]::NewGuid()

Foreach ( $rg in $sourceResourceGroups ) 
{
  #Get the Target Resource Group ARM Template
  New-Item -ItemType directory -Path "$Env:TEMP\AzureMigrationtool" -Force | Out-Null
  $Sourcetemplatepath = $Env:TEMP + "\AzureMigrationtool\$tempId" + "\Source" + $rg + ".json"

  Export-AzureRmResourceGroup -ResourceGroupName $rg -Path $Sourcetemplatepath -IncludeParameterDefaultValue -Force -WarningAction Ignore | Out-Null

  $sourceTemplate = Get-Content -raw -Path $Sourcetemplatepath | ConvertFrom-Json
  $sourceParameters += $sourceTemplate.parameters

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

    if ($resource.ResourceType -eq 'virtualMachines')
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

      $destResourceList.$destRg.Phase5 += $crs
    }
    else
    {
      $targetresource = $srcResourceList.$srcRg.resources | Where-Object { ($_.name -match $name) -and ($_.type -match $resource.ResourceType) }
      $targetresource.location = $targetLocation
      $destResourceList.$destRg.$phase += $targetresource
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

  Foreach ( $rg in $destinationResourceGroups ) {
    
    if ( $destResourceList.$rg.$currentPhase.Count -ne 0 ){
  
      #Set Target ARM Template with source settings
      $targettemplate = New-Object PSObject
      $targettemplate | Add-Member -Name '$schema' -MemberType NoteProperty -Value "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#"
      $targettemplate | Add-Member -Name "contentVersion" -MemberType Noteproperty -Value "1.0.0.0"
      $targettemplate | Add-Member -Name "parameters" -MemberType Noteproperty -Value $null
      $targettemplate | Add-Member -Name "variables" -MemberType Noteproperty -Value $null
      $targettemplate | Add-Member -Name "resources" -MemberType Noteproperty -Value $null

      
      $targettemplate.resources = $destResourceList.$destRg.Phase1

      for ( $j = 2; $j -le $i; $j ++ )
      {
        $addPhase = "Phase" + $j
        $targettemplate.resources += $destResourceList.$destRg.$addPhase
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
                        $resourceCheck.Parent = $v
          
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
          if (( $tmname -match "_name" ) -and ($tmname -notmatch "_name_") )
          {
            if( $tmname.Split("_").Count -eq 3 )
            {
              $sourceName = $tmname.Split("_")[1]
            }
            else
            {
              $sourceName = $tmname.Split("_")[1]
              for ( $i = 2; $i -lt ($tmname.Split("_").Count - 1); $i++ )
              {
                $sourceName = $sourceName + "-" + $tmname.Split("_")[$i]
              }
            }
            
            $targetResource = $vmResources | Where-Object { ($_.SourceName -eq $sourceName ) -and ( $_.DestinationResourceGroup -eq $rg ) -and ( $_.ResourceType -eq $tmname.Split("_")[0] ) }
          
            if ( $targetResource -ne $null )
            { 
              $targetparameters.$tmname.defaultValue = $targetresource.DestinationName
            }
            
          }
        }

        $targettemplate.parameters = $targetparameters
      }
      
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
  #Remove-Item $templatepath* -Force -Recurse

}
else
{
  $templatepath = $Env:TEMP + "\AzureMigrationtool\$tempId"
  #Remove-Item $templatepath* -Force -Recurse

  Throw "The VM Migration is Failed."
}

