# GetSystemHW.ps1
# This script collects system/hardware information along with extended data:
# - Performance Snapshot (CPU, Memory)
# - Networking (Binding Order & Adapter details)
# - Terminal Services (Server settings, Session names)
# - Peripherals (Printers)
# - Installed Programs (from registry)
# - Services
# - Scheduled Tasks
# - Installed Hotfixes and Updates
# - Event Logs (System & Application, recent 30)
# - Firewall Rules

function Get-SystemHW {
    # -------------------------
    # 1. System Information
    # -------------------------
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $culture = Get-Culture
    $timezone = Get-TimeZone

    $systemInfo = @{
        Name                = $env:COMPUTERNAME
        DomainMember        = if ($cs.PartOfDomain) { "Yes" } else { "No" }
        DomainFQDN          = $cs.Domain
        Username            = $env:USERNAME
        InstalledOS         = $os.Caption
        ServicePack         = "$($os.ServicePackMajorVersion).$($os.ServicePackMinorVersion)"
        SystemType          = if ($cs.SystemType -match "64") { "x64" } else { "x86" }
        Version             = $os.Version
        LicenseStatus       = "Unknown"    # Placeholder; adjust as needed
        CurrentSystemLocale = $culture.Name
        CurrentTimeZone     = $timezone.StandardName
    }

    # -------------------------
    # 2. Hardware Information
    # -------------------------
    $physicalMemoryGB = if ($cs.TotalPhysicalMemory) {
        "{0:N2} GB" -f ($cs.TotalPhysicalMemory / 1GB)
    } else { "N/A" }

    $pageFileUsages = Get-CimInstance -ClassName Win32_PageFileUsage
    $pageFileMB = ($pageFileUsages | Measure-Object -Property AllocatedBaseSize -Sum).Sum
    $pageFileGB = if ($pageFileMB) { "{0:N2} GB" -f ($pageFileMB / 1024) } else { "N/A" }

    $processors = Get-CimInstance -ClassName Win32_Processor
    $physicalProcessors = $processors.Count
    $logicalProcessors  = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

    $video = Get-CimInstance -ClassName Win32_VideoController | Select-Object -First 1
    if ($video) {
        $videoName = $video.Name
        if ($video.CurrentHorizontalResolution -and $video.CurrentVerticalResolution) {
            $resolution = "$($video.CurrentHorizontalResolution)x$($video.CurrentVerticalResolution)"
        }
        else {
            $resolution = $video.VideoModeDescription
        }
    }
    else {
        $videoName = "N/A"
        $resolution = "N/A"
    }

    $hardwareInfo = @{
        PhysicalMemory     = $physicalMemoryGB
        PageFileMemory     = $pageFileGB
        PhysicalProcessors = $physicalProcessors
        LogicalProcessors  = $logicalProcessors
        VideoCard          = @{
            Description = $videoName
            Resolution  = $resolution
        }
    }

    # -------------------------
    # 3. Drive Information
    # -------------------------
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
    $driveInfo = @()
    foreach ($drive in $drives) {
        $totalSpaceGB = if ($drive.Size) { "{0:N2} GB" -f ($drive.Size / 1GB) } else { "N/A" }
        $freeSpaceGB  = if ($drive.FreeSpace) { "{0:N2} GB" -f ($drive.FreeSpace / 1GB) } else { "N/A" }
        $driveInfo += @{
            Name       = $drive.DeviceID
            Label      = $drive.VolumeName
            TotalSpace = $totalSpaceGB
            FreeSpace  = $freeSpaceGB
            DriveType  = switch ($drive.DriveType) {
                            2 { "Removable Disk" }
                            3 { "Local Disk" }
                            5 { "CD-ROM" }
                            default { $drive.DriveType }
                         }
            FileSystem = $drive.FileSystem
        }
    }

    # -------------------------
    # 4. Performance Snapshot
    # -------------------------
    try {
        $cpuIdle  = (Get-Counter '\Processor(_Total)\% Idle Time').CounterSamples[0].CookedValue
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
    }
    catch { 
        $cpuIdle = $cpuUsage = "N/A"
    }
    try {
        # Using Win32_OperatingSystem values for memory (in kilobytes)
        $totalMemKB     = $os.TotalVisibleMemorySize
        $freeMemKB      = $os.FreePhysicalMemory
        $totalMemory    = "{0:N2} GB" -f ($totalMemKB * 1KB / 1GB)
        $availableMemory= "{0:N2} GB" -f ($freeMemKB * 1KB / 1GB)
    }
    catch {
        $totalMemory = $availableMemory = "N/A"
    }
    try {
        $pageFaults = (Get-Counter '\Memory\Page Faults/sec').CounterSamples[0].CookedValue
    }
    catch { $pageFaults = "N/A" }

    $performanceSnapshot = @{
        CPU = @{
            IdleTime = if ($cpuIdle -is [string]) { $cpuIdle } else { "{0:N2}%" -f $cpuIdle }
            CPUTime  = if ($cpuUsage -is [string]) { $cpuUsage } else { "{0:N2}%" -f $cpuUsage }
        }
        Memory = @{
            TotalMemory         = $totalMemory
            AvailableMemory     = $availableMemory
            PageFaultsPerSecond = if ($pageFaults -is [string]) { $pageFaults } else { "{0:N2}" -f $pageFaults }
        }
    }

    # -------------------------
    # 5. Networking
    # -------------------------
    # Network Binding Order (using Get-NetIPInterface; requires Windows 8+)
    try {
        $netOrder = Get-NetIPInterface | Sort-Object -Property InterfaceMetric | ForEach-Object { $_.InterfaceAlias }
        $networkBindingOrder = $netOrder -join ", "
    }
    catch { $networkBindingOrder = "N/A" }
    
    # Network Adapters: using CIM instance for IP-enabled adapters
    $netAdapters = @()
    $netConfigs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
    foreach ($adapter in $netConfigs) {
       $netAdapters += @{
          Name             = $adapter.Description
          ConnectionStatus = $adapter.IPConnectionMetric  # Note: may not be a clear status
          DHCPEnabled      = $adapter.DHCPEnabled
          IPAddress        = ($adapter.IPAddress -join ", ")
          SubnetMask       = ($adapter.IPSubnet -join ", ")
          DefaultGateway   = ($adapter.DefaultIPGateway -join ", ")
          DNSAddress       = ($adapter.DNSServerSearchOrder -join ", ")
       }
    }
    $networking = @{
         NetworkBindingOrder = $networkBindingOrder
         NetworkAdapters     = $netAdapters
    }

    # -------------------------
    # 6. Terminal Services
    # -------------------------
    # Attempt to retrieve Terminal Service settings (may require admin rights)
    try {
        $tsSettings = Get-CimInstance -Namespace "root\CIMV2\TerminalServices" -ClassName Win32_TerminalServiceSetting
        if ($tsSettings) {
            $serverSettings = @{
                Name               = $tsSettings.Caption
                TSNode             = $tsSettings.ServerName
                AllowTSConnections = if ($tsSettings.AllowTSConnections -eq 1) { "Y" } else { "N" }
                LicensingType      = $tsSettings.LicensingType
                LicensingName      = if ($tsSettings.LicensedServer) { $tsSettings.LicensedServer } else { "N/A" }
                UserLogonMode      = "N/A"   # Placeholder
                UserPermissions    = "N/A"   # Placeholder
            }
        }
        else {
            $serverSettings = "N/A"
        }
    }
    catch {
        $serverSettings = "N/A"
    }
    # Retrieve session names using 'qwinsta' command
    try {
        $rawSessions = & qwinsta 2>&1
        # Filter lines that contain session info (assuming lines with '>' indicate the active session)
        $sessionNames = $rawSessions | Select-String -Pattern ">" | ForEach-Object { ($_ -split "\s+")[1] }
    }
    catch { $sessionNames = @() }
    $terminalServices = @{
       ServerSettings = $serverSettings
       SessionNames   = $sessionNames
    }

    # -------------------------
    # 7. Peripherals (Printers)
    # -------------------------
    $printers = @()
    try {
       $printerInstances = Get-CimInstance -ClassName Win32_Printer
       foreach ($printer in $printerInstances) {
         $printers += @{
            Name   = $printer.Name
            Driver = $printer.DriverName
            Type   = if ($printer.Network) { "Network" } else { "Local" }
            Port   = $printer.PortName
         }
       }
    }
    catch { $printers = @() }
    $peripherals = @{
       Printers = $printers
    }

    # -------------------------
    # 8. Installed Programs
    # -------------------------
    $programs = @()
    try {
       # Query both 64-bit and 32-bit uninstall registry keys
       $uninstallKeys = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", `
                        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
       foreach ($key in $uninstallKeys) {
          $apps = Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
          foreach ($app in $apps) {
             $status = if ($app.InstallLocation -and ($app.InstallLocation -match "Program Files")) { "Global" } else { "User only" }
             $programs += @{
                Name              = $app.DisplayName
                Version           = $app.DisplayVersion
                Size              = if ($app.EstimatedSize) { "{0} MB" -f $app.EstimatedSize } else { "N/A" }
                InstalledLocation = $app.InstallLocation
                Status            = $status
             }
          }
       }
    }
    catch { $programs = @() }
    $installedPrograms = $programs

    # -------------------------
    # 9. All Services
    # -------------------------
    $services = @()
    try {
       $serviceList = Get-CimInstance -ClassName Win32_Service
       foreach ($svc in $serviceList) {
         $services += @{
            Name        = $svc.Name
            Description = $svc.Description
            Status      = $svc.State
            StartupType = $svc.StartMode
            LogOnAs     = $svc.StartName
         }
       }
    }
    catch { $services = @() }

    # -------------------------
    # 10. Scheduled Tasks
    # -------------------------
    $scheduledTasks = @()
    try {
       # Requires ScheduledTasks module (Windows 8 and later)
       $tasks = Get-ScheduledTask
       foreach ($task in $tasks) {
          try {
              $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
          } catch {
              $taskInfo = $null
          }
          $scheduledTasks += @{
             Name             = $task.TaskName
             Status           = $task.State
             Triggers         = ($task.Triggers | ForEach-Object { $_.ToString() }) -join "; "
             RunTime          = if ($taskInfo) { $taskInfo.LastRunTime } else { "N/A" }
             RunResultHistory = if ($taskInfo) { @($taskInfo.LastTaskResult) } else { @() }
          }
       }
    }
    catch { $scheduledTasks = @() }

    # -------------------------
    # 11. Installed Microsoft Hotfixes and Updates
    # -------------------------
    $hotfixesAndUpdates = @()
    try {
       $hotfixes = Get-HotFix
       foreach ($hotfix in $hotfixes) {
         $hotfixesAndUpdates += @{
            HotFixID    = $hotfix.HotFixID
            Description = $hotfix.Description
            InstalledOn = $hotfix.InstalledOn
         }
       }
    }
    catch { $hotfixesAndUpdates = @() }

    # -------------------------
    # 12. Event Logs (Recent 30 entries for System and Application)
    # -------------------------
    $eventLogs = @{
       System      = @()
       Application = @()
    }
    try {
       $systemLogs = Get-EventLog -LogName System -Newest 30
       foreach ($log in $systemLogs) {
         $eventLogs.System += @{
            TimeGenerated = $log.TimeGenerated
            EntryType     = $log.EntryType
            Source        = $log.Source
            Message       = $log.Message
         }
       }
    }
    catch { $eventLogs.System = @() }
    try {
       $appLogs = Get-EventLog -LogName Application -Newest 30
       foreach ($log in $appLogs) {
         $eventLogs.Application += @{
            TimeGenerated = $log.TimeGenerated
            EntryType     = $log.EntryType
            Source        = $log.Source
            Message       = $log.Message
         }
       }
    }
    catch { $eventLogs.Application = @() }

    # -------------------------
    # 13. Firewall Rules (Full snapshot)
    # -------------------------
    $firewallRules = @()
    try {
       $fwRules = Get-NetFirewallRule
       foreach ($rule in $fwRules) {
         $firewallRules += @{
            Name    = $rule.DisplayName
            Enabled = $rule.Enabled
            Direction = $rule.Direction
            Action  = $rule.Action
            Profile = $rule.Profile
         }
       }
    }
    catch { $firewallRules = @() }

    # -------------------------
    # Combine All Sections into Final Object
    # -------------------------
    $result = @{
        SystemInfo          = $systemInfo
        Hardware            = $hardwareInfo
        DriveInfo           = $driveInfo
        PerformanceSnapshot = $performanceSnapshot
        Networking          = $networking
        TerminalServices    = $terminalServices
        Peripherals         = $peripherals
        InstalledPrograms   = $installedPrograms
        Services            = $services
        ScheduledTasks      = $scheduledTasks
        HotfixesAndUpdates  = $hotfixesAndUpdates
        EventLogs           = $eventLogs
        FirewallRules       = $firewallRules
    }

    return $result
}

# Execute the function and return its output for further processing.
$resultObj = Get-SystemHW
return $resultObj
