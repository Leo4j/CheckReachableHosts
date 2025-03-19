# CheckReachableHosts

Check what hosts are reachable (SMB, WMI, WinRM, or specified port)

## Load in memory

```
iex(new-object net.webclient).downloadstring('https://raw.githubusercontent.com/Leo4j/CheckReachableHosts/refs/heads/main/CheckReachableHosts.ps1')
```

## Usage

```
CheckReachableHosts
```
```
CheckReachableHosts -WMI
```
```
CheckReachableHosts -Targets c:\Users\user\machines.txt
```
```
CheckReachableHosts -Targets "DC01,Workstation01.contoso.local"
```
```
CheckReachableHosts -Domain contoso.local -DomainController dc01.contoso.local
```


