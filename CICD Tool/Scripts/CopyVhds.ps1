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
    if ( $datauri -match 'https' ) {
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