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