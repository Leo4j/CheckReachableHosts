function CheckReachableHosts {
	param(
		[string]$Domain,
		[string]$DomainController,
		[string]$Targets,
		[int]$Port,
		[switch]$WMI,
		[switch]$winrm
	)
	
	if(!$Targets){
				
		# All Domains
		$FindCurrentDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
		if(!$FindCurrentDomain){$FindCurrentDomain = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName.Trim()}
		if(!$FindCurrentDomain){$FindCurrentDomain = $env:USERDNSDOMAIN}
		if(!$FindCurrentDomain){$FindCurrentDomain = Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem | Select Domain | Format-Table -HideTableHeaders | out-string | ForEach-Object { $_.Trim() }}
		
		$ParentDomain = ($FindCurrentDomain | Select-Object -ExpandProperty Forest | Select-Object -ExpandProperty Name)
		$DomainContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $ParentDomain)
		$ChildContext = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContext)
		$ChildDomains = @($ChildContext | Select-Object -ExpandProperty Children | Select-Object -ExpandProperty Name)
		
		$AllDomains = @($ParentDomain)
		
		if($ChildDomains){
			foreach($ChildDomain in $ChildDomains){
				$AllDomains += $ChildDomain
			}
		}
		
		# Trust Domains (save to variable)
		$TrustTargetNames = @(foreach($AllDomain in $AllDomains){(FindDomainTrusts -Domain $AllDomain).TargetName})
		$TrustTargetNames = $TrustTargetNames | Sort-Object -Unique
		$TrustTargetNames = $TrustTargetNames | Where-Object { $_ -notin $AllDomains }
		
		# Remove Outbound Trust from $AllDomains
		$OutboundTrusts = @(foreach($AllDomain in $AllDomains){FindDomainTrusts -Domain $AllDomain | Where-Object { $_.TrustDirection -eq 'Outbound' } | Select-Object -ExpandProperty TargetName})
		
		
		foreach($TrustTargetName in $TrustTargetNames){
			$AllDomains += $TrustTargetName
		}
		
		$AllDomains = $AllDomains | Sort-Object -Unique
		
		$PlaceHolderDomains = $AllDomains
		$AllDomains = $AllDomains | Where-Object { $_ -notin $OutboundTrusts }
		
		### Remove Unreachable domains
		$ReachableDomains = $AllDomains

		foreach($AllDomain in $AllDomains){
			$ReachableResult = $null
			$DomainContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext('Domain', $AllDomain)
			$ReachableResult = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContext)
			if($ReachableResult){}
			else{$ReachableDomains = $ReachableDomains | Where-Object { $_ -ne $AllDomain }}
		}

		$AllDomains = $ReachableDomains
		
		$Computers = @()
		foreach($AllDomain in $AllDomains){
			$Computers += Get-ADComputers -ADCompDomain $AllDomain
		}
		$Computers = $Computers | Sort-Object
	}
	
	else{
		$TestPath = Test-Path $Targets
		
		if($TestPath){
			$Computers = Get-Content -Path $Targets
			$Computers = $Computers | Sort-Object -Unique
		}
		
		else{
			$Computers = $Targets
			$Computers = $Computers -split ","
			$Computers = $Computers | Sort-Object -Unique
		}
	}
	
	if($WMI){$Port = 135}
	elseif($winrm){$Port = 5985}
	elseif($Port){}
	else{$Port = 445}
	
	# Initialize the runspace pool
	$runspacePool = [runspacefactory]::CreateRunspacePool(1, 10)
	$runspacePool.Open()

	# Define the script block outside the loop for better efficiency
	$scriptBlock = {
		param ($computer, $Port)
		
		$tcpClient = New-Object System.Net.Sockets.TcpClient
		$asyncResult = $tcpClient.BeginConnect($computer, $Port, $null, $null)
		$wait = $asyncResult.AsyncWaitHandle.WaitOne(100)
		if ($wait) {
			try {
				$tcpClient.EndConnect($asyncResult)
				return $computer
			} catch {}
		}
		$tcpClient.Close()
		return $null
	}

	# Use a generic list for better performance when adding items
	$runspaces = New-Object 'System.Collections.Generic.List[System.Object]'

	foreach ($computer in $Computers) {
		$powerShellInstance = [powershell]::Create().AddScript($scriptBlock).AddArgument($computer).AddArgument($Port)
		$powerShellInstance.RunspacePool = $runspacePool
		$runspaces.Add([PSCustomObject]@{
			Instance = $powerShellInstance
			Status   = $powerShellInstance.BeginInvoke()
		})
	}

	# Collect the results
	$reachable_hosts = @()
	foreach ($runspace in $runspaces) {
		$result = $runspace.Instance.EndInvoke($runspace.Status)
		if ($result) {
			$reachable_hosts += $result
		}
	}
	
	$HostFQDN = [System.Net.Dns]::GetHostByName(($env:computerName)).HostName
	$reachable_hosts = $reachable_hosts | Where-Object {$_ -ne $HostFQDN}
	$reachable_hosts = $reachable_hosts | Where-Object { $_ -and $_.trim() }
	$reachable_hosts

	# Close and dispose of the runspace pool for good resource management
	$runspacePool.Close()
	$runspacePool.Dispose()
	
}
