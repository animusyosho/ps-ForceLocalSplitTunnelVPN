#Inputs
$Gateway = '192.168.160.117'  	# AP local IP or home network default gateway. Whichever is the next hop from this computer. Knowledge of your local network is required.
$LocalNetwork = '172.26.6.0/24'	# This is your local subnet CIDR address. You can look this up in ipconfig /all
$VPNInterfaceIndex = 17			# This is the interface ID of your VPN interface. To find, use Get-NetIPInterface
$HomeNetworkInterfaceIndex = 20	# This is the interface ID of your Home Network interface (Wi-fi or ethernet). To find, use Get-NetIPInterface

# This script is meant to set local routes on the local route table to forcefully bypass a full-tunnel VPN for traffic with specific destinations.
# Currently, this effects local network traffic (primarily meant for Synergy network KVM) and office365 / onedrive traffic. 
# Some VPN clients may override some of these settings every time you connect. This is tested compatible with OpenConnect-GUI VPN client on Windows 10/11.

# USE THIS AT YOUR OWN RISK. DO NOT USE THIS IF YOU CANNOT TROUBLESHOOT NETWORK ROUTES SHOULD SOMETHING GO WRONG!!

# Set priorities on interfaces.
Set-NetIPInterface -InterfaceIndex $VPNInterfaceIndex -InterfaceMetric 1
Set-NetIPInterface -InterfaceIndex $HomeNetworkInterfaceIndex -InterfaceMetric 2

#Make sure priority of default route to local network is still just below priority of vpn tunnel default route. 
try {
	New-NetRoute -DestinationPrefix 0.0.0.0/0 -InterfaceIndex $HomeNetworkInterfaceIndex -NextHop $Gateway -RouteMetric 1 -ErrorAction Stop | Out-Null
}
catch {
	Set-NetRoute -DestinationPrefix 0.0.0.0/0 -InterfaceIndex $HomeNetworkInterfaceIndex -NextHop $Gateway -RouteMetric 1
}

#Force local traffic through local network.
try {
	New-NetRoute -DestinationPrefix $LocalNetwork -InterfaceIndex $HomeNetworkInterfaceIndex -NextHop $Gateway -RouteMetric 0 -ErrorAction Stop | Out-Null
}
catch {
	Set-NetRoute -DestinationPrefix $LocalNetwork -InterfaceIndex $HomeNetworkInterfaceIndex -NextHop $Gateway -RouteMetric 0
}

# This part of the script originally came from https://docs.microsoft.com/en-us/windows/security/identity-protection/vpn/vpn-office-365-optimization
#Force office365 / onedrive traffic through local network / internet
$intIndexes = $HomeNetworkInterfaceIndex
# Query the web service for IPs in the Optimize category
$ep = Invoke-RestMethod ("https://endpoints.office.com/endpoints/worldwide?clientrequestid=" + ([GUID]::NewGuid()).Guid)
# Output only IPv4 Optimize IPs to $optimizeIps
$destPrefix = $ep | where { $_.category -eq "Optimize" } | Select-Object -ExpandProperty ips | Where-Object { $_ -like '*.*' }
foreach ($intIndex in $intIndexes) {
    # Add routes to the route table
    foreach ($prefix in $destPrefix) { 
		try {
			New-NetRoute -DestinationPrefix $prefix -InterfaceIndex $intIndex -NextHop $gateway -RouteMetric 0 -ErrorAction Stop | Out-Null
		}
		catch {
			Set-NetRoute -DestinationPrefix $prefix -InterfaceIndex $intIndex -NextHop $gateway -RouteMetric 0
		}
	}
}

Write-Output "Please check new route table:"
Get-NetRoute -PolicyStore PersistentStore
