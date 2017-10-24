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
  $Global:StorageMajorVersion = 0
  $Global:ComputeMajorVersion = 0
  $Global:NetworkMajorVersion = 0
  $Global:ProfileMajorVersion = 0
  $Global:ResourcesMajorVersion = 0
  $Global:AzurePowershellVersion = Get-Module -ListAvailable -Name Azure | ForEach-Object {$_.version.toString()}
  Function Check-AzureRmMigrationPSRequirement
  {
    $moduleList = Get-Module -ListAvailable -Name AzureRm.*

    $AzureRmStorage = $moduleList | Where-Object { $_.Name -eq "AzureRm.Storage" }
    $AzureRmCompute = $moduleList | Where-Object { $_.Name -eq "AzureRm.Compute" }
    $AzureRmNetwork = $moduleList | Where-Object { $_.Name -eq "AzureRm.Network" }
    $AzureRmProfile = $moduleList | Where-Object { $_.Name -eq "AzureRm.Profile" }
    $AzureRmResources = $moduleList | Where-Object { $_.Name -eq "AzureRm.Resources" }
    $Global:StorageMajorVersion = $AzureRmStorage.Version.Major
    $Global:ComputeMajorVersion = $AzureRmCompute.Version.Major
    $Global:NetworkMajorVersion = $AzureRmNetwork.Version.Major
    $Global:ProfileMajorVersion = $AzureRmProfile.Version.Major
    $Global:ResourcesMajorVersion = $AzureRmResources.Version.Major
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
    Check-AzurePSModule -module $AzureRmNetwork
    Check-AzurePSModule -module $AzureRmProfile
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
    #[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
    #[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.MessageBox
    Add-Type -AssemblyName System.Windows.Forms.MessageBoxButtons
    Add-Type -AssemblyName System.Windows.Forms.MessageBoxIcon
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

$Global:JobId = New-Guid | %{ $_.Guid }
$Global:timeSpanList = @()
Function MigrationTelemetry {
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
    $path = Get-Location | %{$_.Path}

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

    $Global:timeSpanList += $timeSpan

    #just record the start time when phase name was not provided, so no table upgrade
    if($phaseName -eq "") {return}

    
    $dic = @{}
    $dic.Add("AzurePowershellVersion",$Global:AzurePowershellVersion)
    $dic.Add("Completed",$completed.IsPresent)
    $dic.Add("VmProfile",(ConvertTo-Json $vmProfile))
    $dic.Add("SourceEnvironment",$srcContext.Environment.Name)
    $dic.Add("DestinationEnvironment",$destContext.Environment.Name)
    $dic.Add("VmSize",$vmProfile.HardwareProfile.VmSize)
    $dic.Add("VmLocation",$vmProfile.Location)
    $dic.Add("VmOsType",$vmProfile.StorageProfile.OsDisk.OsType)
    $dic.Add("VmNumberOfDataDisk",$vmProfile.StorageProfile.DataDisks.Count)

    $srcAccountId = ""
    if($Global:ProfileMajorVersion -ge 3) {
      $dic.Add("SourceSubscriptionId",$srcContext.Subscription.Id)
      $dic.Add("SourceTenantId",$srcContext.Tenant.Id)
      $dic.Add("DestinationSubscriptionId",$destContext.Subscription.Id)
      $dic.Add("DestinationTenantId",$destContext.Tenant.Id)
      $srcAccountId = $srcContext.Account.Id
    }
    else {
      $dic.Add("SourceSubscriptionId",$srcContext.Subscription.SubscriptionId)
      $dic.Add("SourceTenantId",$srcContext.Tenant.TenantId)
      $dic.Add("DestinationSubscriptionId",$destContext.Subscription.SubscriptionId)
      $dic.Add("DestinationTenantId",$destContext.Tenant.TenantId)
      $srcAccountId = $srcContext.Account
    }

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
    } -ArgumentList $path, $srcAccountId, $Global:JobId, $dic | Receive-Job -Wait -AutoRemoveJob

}
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
        default { Throw "User did not select any environment or cancel."}
      }

      [Windows.Forms.MessageBox]::Show("Please Enter " + $SrcEnv + " credential after click OK", "Azure Global Connection Center", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      Add-AzureRmAccount -EnvironmentName $SrcEnvironment | Out-Null

      $subscriptions = Get-AzureRmSubscription
      $subList = @()

      ForEach ( $sub in $subscriptions )
      {
        if($Global:ProfileMajorVersion -ge 3) {
          $subList += $sub.Name
        }
        else {
          $subList += $sub.SubscriptionName
        }
      }

      $subscription = SelectionBox -title "Please Select the Source Subscription" -options $subList

      if($Global:ProfileMajorVersion -ge 3) {
        Select-AzureRmSubscription -Subscription $Subscription | Out-Null
      }
      else {
        Select-AzureRmSubscription -SubscriptionName  $Subscription | Out-Null
      }
      $SrcContext = Get-AzureRmContext
    }

    MigrationTelemetry -srcContext $SrcContext

    if ($DestContext -eq $null )
    {
      if ([string]::IsNullOrEmpty($destEnvironment))
      {
        $destEnv = SelectionBox -title "Please Select the Destination Environment" -options ("Azure in China (operated by 21 vianet)", "Microsoft Azure in Germany", "Microsoft Azure")
        Switch ( $destEnv )
        {
          "Azure in China (operated by 21 vianet)" { $destEnvironment = [AzureEnvironment] "AzureChinaCloud" }
          "Microsoft Azure in Germany" { $destEnvironment = [AzureEnvironment] "AzureGermanCloud" }
          "Microsoft Azure" { $destEnvironment = [AzureEnvironment] "AzureCloud" }
          default { Throw "User did not select any environment or cancel."}
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
        if($Global:ProfileMajorVersion -ge 3) {
          $subList += $sub.Name
        }
        else {
          $subList += $sub.SubscriptionName
        }
      }

      $subscription = SelectionBox -title "Please Select the Desitnation Subscription" -options $subList

      if($Global:ProfileMajorVersion -ge 3) {
        Select-AzureRmSubscription -Subscription $Subscription | Out-Null
      }
      else {
        Select-AzureRmSubscription -SubscriptionName  $Subscription | Out-Null
      }

      $DestContext = Get-AzureRmContext
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
      
      $RenameConfirm = [System.Windows.Forms.MessageBox]::Show("Do you want to change VM configuration?" , "Azure Global Connection Toolkit" , 4)
      if ($RenameConfirm -eq "Yes")
      {
        $RenameInfos = .\Rename.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext
      }
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
        $validationResult = .\Validate.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
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
        .\Preparation.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
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
        $diskUris,$vm = .\CopyVhds.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
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
        .\VMBuild.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -osDiskUri $osDiskUri -dataDiskUris $dataDiskUris -RenameInfos $RenameInfos
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
        $RenameInfos = .\Rename.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext
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
      $validationResult = .\Validate.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
    }
    Catch
    {
      Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
      MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Failed
      Throw "Validation Failed. Please check the error message and try again."
    }
    
    while ($validationResult.Result -eq "Failed")
    {
      
      Write-Host "Validation Failed. Please check following error messages:" -ForegroundColor Red

      foreach ($message in $validationResult.Messages)
      {
        Write-Host $message -ForegroundColor Red        
      }

      $RenameConfirm = [System.Windows.Forms.MessageBox]::Show("Validation Failed. Do you want to change VM configuration?" , "Azure Global Connection Toolkit" , 4)
      if ($RenameConfirm -eq "Yes")
      {
        $RenameInfos = .\Rename.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext
      }
      else
      {
        MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Failed
        Throw "Validation Failed. Please check the error message and try again."
      }

      Try
      {
        $validationResult = .\Validate.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
      }
      Catch
      {
        Write-Host ($_.CategoryInfo.Activity + " : " + $_.Exception.Message) -ForegroundColor Red
        MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -completed -phaseStatus Failed
        Throw "Validation Failed. Please check the error message and try again."
      }
    }

    MigrationTelemetry -srcContext $SrcContext -destContext $DestContext -vmProfile $vm -phaseName "PreValidation" -phaseStatus Succeed
    

    Try
    {
      .\Preparation.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
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
      $diskUris,$vm = .\CopyVhds.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -RenameInfos $RenameInfos
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
      .\VMBuild.ps1 -vm $vm -targetLocation $targetLocation -SrcContext $SrcContext -DestContext $DestContext -osDiskUri $diskUris.osDiskUri -dataDiskUris $diskUris.dataDiskUris -RenameInfos $RenameInfos
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
