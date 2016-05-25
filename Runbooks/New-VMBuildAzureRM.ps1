##Requires -Module Azurerm
<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   New-VMBuildAzureRM -VMName vmDev2-01 -VNetName vnDev2 -SubnetName snDev2 -StorageAccountName saDev2 -ResourceGroupName rgDev2 -SNAddressPrefix 10.100.2.0/24
.EXAMPLE
   New-VMBuildAzureRM -VMName vmDev3-01,vmDev3-02 -VNetName vnDev3 -SubnetName snDev3-01 -StorageAccountName saDev3 -ResourceGroupName rgDev3 -SNAddressPrefix 10.100.3.0/24
.EXAMPLE
   New-VMBuildAzureRM -VMName vmDev1-01,vmDev1-02 -VNetName vnDev1 -SubnetName snDev1-01 -StorageAccountName saDev1 -ResourceGroupName rgDev1 -SNAddressPrefix 10.100.1.0/24 -AddGatway
#>
function New-VMBuildAzureRM
{
    [CmdletBinding()]
    Param
    (
        # Choose the VirtualMachine Name
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [String[]]$VMName,

        # Choose the VNET name for the Virtual Machine
        [Parameter(Mandatory=$true)]
        [String]$VNetName,

        [String]$AvailabilitySetName,

        # Choose the VNET Address Prefix
        [String]$VNetAddressPrefix = "10.100.0.0/16",
        
        # Choose the VNET Subnet Address Prefix
        [Parameter(Mandatory=$true)]
        [String]$SNAddressPrefix,

        # Choose the Subnet name for the Virtual Machine
        [Parameter(Mandatory=$true)]
        [String]$SubnetName,

        # Choose to add a gateway for the VNet
        [Parameter()]
        [Switch]$AddGatway,

        # Choose the StorageAccount Name that you wish to add the VirtualMachine
        # Should be all lower case
        [Parameter(Mandatory=$true)]
        [String]$StorageAccountName,

        # Choose the ResourceGroup Name that you wish to add the VirtualMachine
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,

        # Choose the Instance Size of the Virtual Machine
        [ValidateSet('ExtraSmall','Small','Medium','Large')]
        [String]$VMInstanceSize = 'Small',

        # Choose the Subscription that you wish to add the VirtualMachine
        [ValidateSet('MSFT','BRW')]
        [String]$Subscription = 'MSFT',

        # Choose the Location that you wish to add the VirtualMachine
        [ValidateSet('EASTUS2','EASTUS')]
        [String]$Location = 'EastUS',

        # Choose the StorageType Name that you wish to add the VirtualMachine
        [ValidateSet('Standard_GRS')]
        [String]$StorageType = 'Standard_GRS',

        # Choose the Windows Image for the VirtualMachine
        [ValidateSet('2008-R2-SP1','2012-Datacenter','2012-R2-Datacenter','2016-Nano-Docker-Test',
                        '2016-Nano-Server-Technical-Preview','2016-Nano-Server-Technical-Preview-with-Containers',
                        '2016-Technical-Preview-with-Containers','Windows-Server-Technical-Preview')]
        [String]$WindowsImage = '2012-R2-Datacenter',
        [String]$TimeZone = [System.TimeZoneInfo]::Local.Id,
        [String]$LocalAdminUser = 'Myroot'
    )

    Begin
    {   
        #region Subscription
        Switch ($Subscription)
        {
            'MSFT' {
                        # this is just a sample script make sure that you are connected to azure
                        # with the correct subscription here
                    }
            'MSDN'  {
                        # Set-MyAzureSubscription -SubscriptionName MSDN
                    }
        }#Switch
        #endregion
        #region Resource Group
        try {
            $ResourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        }
        Catch {
            Write-Warning $_
            Write-Warning "Creating resource group: $ResourceGroupName"
            $ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
        }#Catch
        #endregion
        #region StorageAccount
        Try {
            $StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name ($StorageAccountName).tolower() -ErrorAction Stop
        }
        Catch {   
            Write-Warning $_
            Write-Warning "Creating storage account: $StorageAccountName"
            $StorageAccountParams = @{
                ResourceGroupName = $ResourceGroupName 
                Name              = ( $StorageAccountName ).ToLower()
                Type              = $StorageType 
                Location          = $Location
                }
            $StorageAccount = New-AzureRmStorageAccount @StorageAccountParams
        }#Catch

        $VHDPath = $StorageAccount.PrimaryEndpoints.Blob.OriginalString + 'vhds/'

        #endregion
        #region VM Windows Image
        $Publisher = Get-AzureRmVMImagePublisher -Location $Location | where PublisherName -EQ MicrosoftWindowsServer
        
        $Offer = Get-AzureRmVMImageOffer -Location $Location -PublisherName $Publisher.PublisherName
        
        $MySKU = Get-AzureRmVMImageSku  -Location $Location -PublisherName $Publisher.PublisherName -Offer $Offer.Offer | 
                   Where Skus -EQ $WindowsImage | Foreach Skus

        #endregion
        #region OS Configuration settings
        # create your own keyvault with the admin password that you need for the local admin
        $SS= Get-AzureKeyVaultSecret -VaultName MyKeyVault -Name admin
        $Cred = [PSCredential]::new($LocalAdminUser, $SS.SecretValue)
        
        $OSConfiguration = @{
            Windows             = $true
            Credential          = $Cred
            TimeZone            = $TimeZone
            #WinRMCertificateUrl = $WinRMCertUrl
            #WinRMHttps          = $true
            #WinRMHttp           = $true
            }
        #endregion
        #region Virtual Network
        Try {
            $VNET = Get-AzureRmVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop
        }
        Catch {
            Write-Warning $_
            Write-Warning "Creating VNET: $VNetName"            
                        
            $VNetParam = @{
                Name              = $VNetName 
                ResourceGroupName = $ResourceGroupName 
                Location          = $Location 
                AddressPrefix     = $VNetAddressPrefix
                }

            $VNet = New-AzureRmVirtualNetwork @VNetParam
        }
        #endregion
        #region Virtual Network
        $VNetSN = Get-AzureRmVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop |
                foreach Subnets | where Name -EQ $SubnetName
        if (-not $VNetSN)
        {
            Write-Warning $_
            Write-Warning "Creating Subnet: $SubnetName in VNet: $VNetName"
            
            Add-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $VNet -AddressPrefix $SNAddressPrefix
            $VNetSN = Set-AzureRmVirtualNetwork -VirtualNetwork $VNet |
                foreach Subnets | where Name -EQ $SubnetName
        }
        #endregion        
        #region Gateway Subnet
        if ($AddGatway)
        {
            Try {
                $VNETSNGW = Get-AzureRmVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop |
                    foreach Subnets | where Name -EQ 'GatewaySubnet'
            }
            Catch {
                Write-Warning $_
                Write-Warning "Creating Subnet: GatewaySubnet in VNet: $VNetName"
            
                # Set the GatewaySubnet to always be x.x.254.x/24
                $GWPrefix = ($SNAddressPrefix -split '\.')
                $GWPrefix[2] = 254
                $GWPrefix = $GWPrefix -join "."

                $GWPrefix = $SNAddressPrefix
                Add-AzureRmVirtualNetworkSubnetConfig -Name GatewaySubnet -VirtualNetwork $VNet -AddressPrefix $GWPrefix 
                $VNetSNGW = Set-AzureRmVirtualNetwork -VirtualNetwork $VNet
            }
        }
        #endregion
        #region Instance Size
        $VMSize = Switch ($VMInstanceSize)
        {
            ExtraSmall {'Standard_A0'}
            Small      {'Standard_A1'}
            Medium     {'Standard_A2'}
            Large      {'Standard_A3'}
        }

        #endregion

    }#Begin
    Process
    {
        $VMName | ForEach-Object {
            $VM = $_
            $OSConfiguration['ComputerName'] = $VM
            #region Public IP       
            Try {
                $PublicIP = Get-AzureRmPublicIpAddress -ResourceGroupName $ResourceGroupName -Name ('PublicIP_' + $VM) -ErrorAction Stop
            }
            Catch {
                Write-Warning $_
                Write-Warning "Creating PublicIP for VM: $VM"            
                $PublicIPParam = @{
                    Name              = ('PublicIP_' + $VM) 
                    ResourceGroupName = $ResourceGroupName 
                    Location          = $Location 
                    AllocationMethod  = 'Dynamic'
                    }
                $PublicIP = New-AzureRmPublicIpAddress @PublicIPParam
            }
            #endregion
            #region Network Interface
            Try {
                $Interface = Get-AzureRmNetworkInterface -Name ('NIC_' + $VM) -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            }
            Catch {

                Write-Warning -Message "Creating Interface $('NIC_' + $VM)"
                $NetworkInterfaceParams = @{
                    Name              = ('NIC_' + $VM) 
                    ResourceGroupName = $ResourceGroupName 
                    Location          = $Location 
                    SubnetId            = $VNETSN.Id
                    PublicIpAddressId = $PublicIP.Id
                    }

                $Interface = New-AzureRmNetworkInterface @NetworkInterfaceParams
                
                # Lots of stuff here
                # New-AzureRmNetworkInterface -Name -ResourceGroupName -Location -SubnetId -PublicIpAddressId `
                # -PrivateIpAddress -LoadBalancerBackendAddressPoolId -LoadBalancerInboundNatRuleId `
                # -NetworkSecurityGroupId -IpConfigurationName -DnsServer -InternalDnsNameLabel -EnableIPForwarding
            }
            #endregion
            #region VMConfig
            $VMConfig = @{
                Name   = $VM 
                VMSize = $VMSize
                }
            #endregion
            #region Availability Set
            if ($AvailabilitySetName)
            {
                try {
                    $AvailabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $AvailabilitySetName -ErrorAction Stop
                }
                Catch {
                    $AvailabilitySet = New-AzureRmAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $AvailabilitySetName -Location $Location
                }

                $VMConfig['AvailabilitySetId'] = $AvailabilitySet.ID 
            }
            #endregion

            $MyVM = New-AzureRMVMConfig @VMConfig  | 
                Set-AzureRmVMSourceImage -PublisherName $publisher.PublisherName -Offer $offer.Offer -Skus  $MySKU -Version latest |
                Set-AzureRmVMOperatingSystem @OSConfiguration |
                Set-AzureRmVMOSDisk -Name ($VM + "_OSDisk") -VhdUri ($VHDPath + $VM + "_OSDisk.vhd") -CreateOption FromImage |
                Add-AzureRmVMNetworkInterface -Id $Interface.Id |
                Add-AzureRmVMDataDisk -Name ($VM + "_DataDisk") -VhdUri ($VHDPath + $VM + "_DataDisk.vhd") -Caching ReadWrite -DiskSizeInGB 127 -Lun 0 -CreateOption empty

            #region DSC Agent
            if ($BootStrapDSC)
            {
                $DSCExtension = @{
                        # ConfigurationArgument: supported types for values include: primitive types, string, array and PSCredential
                        ConfigurationArgument= @{
                                ComputerName = 'localhost'
                                }           
                        ArchiveStorageAccountName = 'saeastus01'
                        ArchiveResourceGroupName  = 'rgGlobal'
                        # --- Info above about the DSC Resource

                        # --- Info Below about the Virtual Machine                  
                        ResourceGroupName    = $ResourceGroupName
                        VMName               = $VM
                        Location             = $Location
                        ConfigurationName    = 'BaseOS'
                        ConfigurationArchive = 'BaseOS.ps1.zip'
                        Version              = (Get-AzureVMAvailableExtension -ExtensionName DSC -Publisher Microsoft.Powershell | Foreach Version)
                        WmfVersion           = 'latest'
                        AutoUpdate           = $true
                        Force                = $True
                        Verbose              = $True
                      }
            
               $MyVM = $MyVM | Set-AzureRmVMDscExtension @DSCExtension
               
            }#BootStrapDSC
            #endregion

            Write-Verbose -Message "Adding VM $VM to $ResourceGroupName" -Verbose
            try {
                $MyVM.ConfigurationSets
                $MyVM.ResourceExtensionReferences

                New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $MyVM -ErrorAction Stop

                if (-not $Wait)
                {
                  $New = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM
                  $New | Select Name,ResourceGroupName, Location, ProvisioningState
$message = @"
Provisioning $VM this will take some time
         Run the following to get status update:`n
         Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM | 
          select Name,ResourceGroupName, Location, ProvisioningState `n
"@                  
                  Write-Verbose -Message $message -Verbose
                  [console]::Beep(15kb,400)
                  #Continue
                }
                else{
            
                    do { 
                      $New = Get-AzureVM -Name $VM -ServiceName $ServiceName
                      $New
                      If ($BootStrapDSC)
                      {
                        $New.ResourceExtensionStatusList.Where{$_.HandlerName -eq 'Microsoft.Powershell.DSC'}.ExtensionSettingStatus.FormattedMessage
                      }
                      Write-Verbose -Message "Waiting for $VM : $(Get-Date)" -verbose
                      Start-Sleep -Seconds 20
                    } 
                    while ($New.Status -in 'Provisioning','RoleStateUnknown')
                }#Else
            }
            Catch {
                Write-Warning $_
            }
            [console]::Beep(15kb,400)
        }
    }#Process
}#New-VMBuildAzure