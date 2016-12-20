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
   
   $resourceCheck = $vmResources | Where-Object { ($_.SourceName -eq $resource.SourceName) -and ($_.ResourceType -eq $resource.ResourceType) -and ($_.SourceResourceGroup -eq $resource.SourceResourceGroup) }
   
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
   if ( $osuri -match "https" ) {
   $datastorname = $datauri.Substring(8, $datauri.IndexOf(".blob") - 8)}
   else {
    $datastorname = $datauri.Substring(7, $datauri.IndexOf(".blob") - 7)
   }
   Add-StorageList -storName $datastorname
}


####Rename Function####
$RenameFunction = {
Class ResourceProfile
{
   [String] $ResourceType
   [String] $SourceResourceGroup
   [String] $DestinationResourceGroup
   [String] $SourceName
   [String] $DestinationName
}
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
Function Rename {
Param(
    [Parameter(Mandatory=$True)]
    [AllowNull()]
    [Object[]] 
    $vmResources
)
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
$objLabel.Text = "Please Rename Following Resources"
$objForm.Controls.Add($objLabel) 

$objListbox = New-Object System.Windows.Forms.DataGridView -Property @{
  ColumnHeadersVisible = $true
  RowHeadersVisible = $false
  location = New-Object System.Drawing.Size(10,70)
  Size = New-Object System.Drawing.Size(750,420)
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

$renameInfos = @()
$result | ForEach { 
    $renameInfo = New-Object ResourceProfile;
    $renameInfo.ResourceType = $_.ResourceType;
    $renameInfo.SourceResourceGroup = $_.SourceResourceGroup;
    $renameInfo.DestinationResourceGroup = $_.DestinationResourceGroup;
    $renameInfo.SourceName = $_.SourceName;
    $renameInfo.DestinationName = $_.DestinationName;
    $renameInfos += $renameInfo;
    }
return $renameInfos
