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

