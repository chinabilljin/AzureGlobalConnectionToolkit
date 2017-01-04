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
$RenameExcute = {
$Runspace = [runspacefactory]::CreateRunspace()
$PowerShell = [powershell]::Create()
$Runspace.ApartmentState = "STA"
$Runspace.ThreadOptions = "ReuseThread"
$PowerShell.runspace = $Runspace
$Runspace.Open()
[void]$PowerShell.AddScript({
Param ($Param1, $Param2, $Param3)
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
      [Object[]] 
      $vmResources,

      [Parameter(Mandatory=$True)]
      [string] $vmSize,

      [Parameter(Mandatory=$True)]
      [Object[]] 
      $vmSizeList
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

    $objForm.Controls.Add($OKButton) | Out-Null

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Location = New-Object System.Drawing.Size(200,500)
    $CancelButton.Size = New-Object System.Drawing.Size(180,40)
    $CancelButton.Text = "Cancel"
    $CancelButton.Font = $Buttonfont
    $CancelButton.BackColor = "Gainsboro"

    $CancelButton.Add_Click({$objForm.Close()}) | Out-Null
    $objForm.Controls.Add($CancelButton) | Out-Null

    $objFont = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Italic)
    $objLabel = New-Object System.Windows.Forms.Label
    $objLabel.Location = New-Object System.Drawing.Size(10,20) 
    $objLabel.AutoSize = $True
    $objLabel.BackColor = "Transparent"
    $objLabel.ForeColor = "White"
    $objLabel.Font = $objFont
    $objLabel.Text = "Please Check the Name of Following Resources"
    $objForm.Controls.Add($objLabel) | Out-Null

    $objFont2 = New-Object System.Drawing.Font("Arial",10,[System.Drawing.FontStyle]::Regular)
    $objLabel2 = New-Object System.Windows.Forms.Label
    $objLabel2.Location = New-Object System.Drawing.Size(10,55) 
    $objLabel2.AutoSize = $True
    $objLabel2.BackColor = "Transparent"
    $objLabel2.ForeColor = "LightSteelBlue"
    $objLabel2.Font = $objFont2
    $objLabel2.Text = "Resource List"
    $objForm.Controls.Add($objLabel2) | Out-Null

    $objListbox = New-Object System.Windows.Forms.DataGridView -Property @{
      ColumnHeadersVisible = $true
      RowHeadersVisible = $false
      location = New-Object System.Drawing.Size(10,80)
      Size = New-Object System.Drawing.Size(750,210)
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
  
    $objForm.Controls.Add($objListbox) | Out-Null
    
    $objLabel3 = New-Object System.Windows.Forms.Label
    $objLabel3.Location = New-Object System.Drawing.Size(10,310) 
    $objLabel3.AutoSize = $True
    $objLabel3.BackColor = "Transparent"
    $objLabel3.ForeColor = "LightSteelBlue"
    $objLabel3.Font = $objFont2
    $objLabel3.Text = "DNS Name List"
    $objForm.Controls.Add($objLabel3) | Out-Null
        
    $objDnsbox = New-Object System.Windows.Forms.DataGridView -Property @{
      ColumnHeadersVisible = $true
      RowHeadersVisible = $false
      location = New-Object System.Drawing.Size(10,335)
      Size = New-Object System.Drawing.Size(750,45)
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
    
    $objForm.Controls.Add($objDnsbox) | Out-Null

    $objLabel4 = New-Object System.Windows.Forms.Label
    $objLabel4.Location = New-Object System.Drawing.Size(10,395) 
    $objLabel4.AutoSize = $True
    $objLabel4.BackColor = "Transparent"
    $objLabel4.ForeColor = "LightSteelBlue"
    $objLabel4.Font = $objFont2
    $objLabel4.Text = "VM Size"
    $objForm.Controls.Add($objLabel4) | Out-Null
        
    $objSizebox = New-Object System.Windows.Forms.DataGridView -Property @{
      ColumnHeadersVisible = $true
      RowHeadersVisible = $false
      location = New-Object System.Drawing.Size(10,415)
      Size = New-Object System.Drawing.Size(750,45)
      AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
      EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
      Height = 320
      Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Regular)
      AllowUserToAddRows = $false
    }
    
    $objSizebox.ColumnCount = 4

    $objSizebox.EnableHeadersVisualStyles = $false
    $objSizebox.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Bold)
    $objSizebox.ColumnHeadersDefaultCellStyle.ForeColor = "MidnightBlue"
  
    $objSizebox.Columns[0].Name = "ResourceType"
    $objSizebox.Columns[0].ReadOnly = $True
    $objSizebox.Columns[0].DefaultCellStyle.BackColor = "Gainsboro"

    $objSizebox.Columns[1].Name = "SoureResourceGroup"
    $objSizebox.Columns[1].ReadOnly = $True
    $objSizebox.Columns[1].DefaultCellStyle.BackColor = "Gainsboro"

    $objSizebox.Columns[2].Name = "SourceVmName"
    $objSizebox.Columns[2].ReadOnly = $True
    $objSizebox.Columns[2].DefaultCellStyle.BackColor = "Gainsboro"
    
    $objSizebox.Columns[3].Name = "SourceVmSize"
    $objSizebox.Columns[3].ReadOnly = $True
    $objSizebox.Columns[3].DefaultCellStyle.BackColor = "Gainsboro"
    

    $vmSizeColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $objSizebox.Columns.Add($vmSizeColumn) | Out-Null

    foreach ( $vs in $vmSizeList  )
    {
      $vmSizeColumn.Items.Add($vs.name) | Out-Null
    }
    
    $vmSizeColumn.Name = "DestinationVmSize"


    $vmResources | Where-Object {$_.ResourceType -eq "virtualMachines"} | ForEach { $objSizebox.rows.Add( $_.ResourceType , $_.SourceResourceGroup, $_.SourceName, $vmSize)  } | Out-Null
    
    $objForm.Controls.Add($objSizebox) | Out-Null

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
      return $renameInfos
    }
    else
    {
      $objForm.Dispose()

      break
    }

    
  }
        Rename -vmResources $Param1 -vmSize $Param2 -vmSizeList $Param3

    }).AddArgument($args[0]).AddArgument($args[1]).AddArgument($args[2])
    return $PowerShell.Invoke()
}

$vmSizeList = Get-AzureRmVMSize -Location eastasia | Select-Object -Property Name

$job = Start-Job -ScriptBlock $RenameExcute -ArgumentList $Script:vmResources, $vm.HardwareProfile.VmSize, $vmSizeList
$result = $job | Receive-Job -Wait -AutoRemoveJob

$resultValidate = $false

While (!$resultValidate)
{
  $resultValidate = $True

  foreach ( $r in $result )
  {
    if (($r.ResourceType -ne "storageAccounts") -and (!([string]::IsNullOrEmpty($r.ResourceType))))
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
    $job = Start-Job -ScriptBlock $RenameExcute -ArgumentList $Script:vmResources, $vm.HardwareProfile.VmSize, $vmSizeList
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
