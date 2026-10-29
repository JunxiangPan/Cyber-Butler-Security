#Requires -Version 5.1
<#
Cyber-Butler dashboard module loader.

A module is a directory under tools/dashboard_plugins/<id>/ containing:

    manifest.json   identity and file names (required)
    ui.xaml         the tab content (required)
    logic.ps1       optional PowerShell that wires the UI

The loader is intentionally defensive: a broken manifest, a malformed XAML or a
logic script that throws only disables that one module. The host keeps running
and reports "模块 xxx 加载失败" in the module manager. Unhandled exceptions in
module event handlers are caught by the dispatcher hook registered here.
#>

$script:DashboardModuleStateFile = Join-Path $env:LOCALAPPDATA 'CyberButler\dashboard-modules.json'
$script:DashboardModuleLogFile = Join-Path $env:LOCALAPPDATA 'CyberButler\dashboard-modules.log'
$script:LoadedDashboardModules = @{}
$script:DashboardModuleExceptionHook = $false

function Write-DashboardModuleLog {
    param([string]$Message)
    try {
        $dir = Split-Path -Parent $script:DashboardModuleLogFile
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ((Test-Path -LiteralPath $script:DashboardModuleLogFile) -and
            ((Get-Item -LiteralPath $script:DashboardModuleLogFile).Length -gt 512KB)) {
            Move-Item -LiteralPath $script:DashboardModuleLogFile -Destination ($script:DashboardModuleLogFile + '.1') -Force -ErrorAction SilentlyContinue
        }
        Add-Content -LiteralPath $script:DashboardModuleLogFile -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

function Read-DashboardModuleState {
    $state = @{ disabled = @() }
    if (-not (Test-Path -LiteralPath $script:DashboardModuleStateFile)) { return $state }
    try {
        $saved = Get-Content -LiteralPath $script:DashboardModuleStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved -and $saved.PSObject.Properties.Name -contains 'disabled') {
            $state.disabled = @($saved.disabled | ForEach-Object { [string]$_ })
        }
    } catch { }
    return $state
}

function Save-DashboardModuleState($State) {
    try {
        $dir = Split-Path -Parent $script:DashboardModuleStateFile
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:DashboardModuleStateFile -Encoding UTF8
    } catch { }
}

function Get-DashboardModules {
    param([string]$ToolsRoot)
    if (-not $ToolsRoot) { $ToolsRoot = $script:ToolsRoot }
    $modulesRoot = Join-Path $ToolsRoot 'dashboard_plugins'
    $state = Read-DashboardModuleState
    $modules = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $modulesRoot)) {
        return [pscustomobject]@{ Root = $modulesRoot; Modules = @() }
    }

    foreach ($folder in @(Get-ChildItem -LiteralPath $modulesRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $manifestPath = Join-Path $folder.FullName 'manifest.json'
        $entry = [pscustomobject]@{
            Id          = $folder.Name
            Name        = $folder.Name
            Version     = ''
            Author      = ''
            Description = ''
            Path        = $folder.FullName
            UiPath      = ''
            LogicPath   = ''
            Enabled     = $true
            Problem     = ''
            DefaultEnabled = $true
        }
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            $entry.Problem = '缺少 manifest.json'
            $entry.Enabled = $false
            [void]$modules.Add($entry)
            continue
        }
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $manifest) { throw 'manifest.json 为空' }
            if ($manifest.id) { $entry.Id = [string]$manifest.id }
            if ($manifest.name) { $entry.Name = [string]$manifest.name }
            if ($manifest.version) { $entry.Version = [string]$manifest.version }
            if ($manifest.author) { $entry.Author = [string]$manifest.author }
            if ($manifest.description) { $entry.Description = [string]$manifest.description }
            if ($manifest.PSObject.Properties.Name -contains 'default_enabled') {
                $entry.DefaultEnabled = [bool]$manifest.default_enabled
            }
            $uiName = if ($manifest.ui) { [string]$manifest.ui } else { 'ui.xaml' }
            $logicName = if ($manifest.logic) { [string]$manifest.logic } else { 'logic.ps1' }
            $entry.UiPath = Join-Path $folder.FullName $uiName
            $entry.LogicPath = Join-Path $folder.FullName $logicName
            if ($entry.Id -notmatch '^[A-Za-z0-9_\-]{2,64}$') { throw ('模块 id 非法：' + $entry.Id) }
            if (-not (Test-Path -LiteralPath $entry.UiPath)) { throw ('缺少 UI 文件：' + $uiName) }
            if (-not (Test-Path -LiteralPath $entry.LogicPath)) { $entry.LogicPath = '' }
        } catch {
            $entry.Problem = $_.Exception.Message
        }

        $isDisabled = ($state.disabled -contains $entry.Id)
        if ($entry.Problem) {
            $entry.Enabled = $false
        } else {
            $entry.Enabled = if ($isDisabled) { $false } else { $true }
        }
        [void]$modules.Add($entry)
    }

    return [pscustomobject]@{ Root = $modulesRoot; Modules = @($modules) }
}

function Import-DashboardModule {
    param(
        [Parameter(Mandatory = $true)]$Module,
        [Parameter(Mandatory = $true)]$Tabs,
        [string]$ToolsRoot = ''
    )

    if (-not $ToolsRoot) { $ToolsRoot = $script:ToolsRoot }
    $result = [pscustomobject]@{ Ok = $false; Id = $Module.Id; Name = $Module.Name; Error = ''; Tab = $null }
    if ($Module.Problem) { $result.Error = $Module.Problem; return $result }
    if (-not $Tabs) { $result.Error = 'TabControl 不可用'; return $result }

    try {
        $xamlText = Get-Content -LiteralPath $Module.UiPath -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
        $root = [Windows.Markup.XamlReader]::Load($reader)
        if (-not $root) { throw 'XAML 解析结果为空' }
    } catch {
        $result.Error = 'UI 加载失败：' + $_.Exception.Message
        Write-DashboardModuleLog ('[' + $Module.Id + '] ' + $result.Error)
        return $result
    }

    $tab = New-Object Windows.Controls.TabItem
    $moduleId = [string]$Module.Id
    $tab.Header = $Module.Name
    $tab.Content = $root
    $tooltip = ('模块 v{0}' -f $Module.Version)
    if ($Module.Author) { $tooltip += ' · ' + $Module.Author }
    if ($Module.Description) { $tooltip += "`n" + $Module.Description }
    $tab.ToolTip = $tooltip
    [void]$Tabs.Items.Add($tab)

    $context = @{
        Id          = $Module.Id
        Name        = $Module.Name
        Version     = $Module.Version
        Author      = $Module.Author
        Module      = $Module
        Root        = $root
        Tab         = $tab
        Host        = $window
        ToolsRoot   = $ToolsRoot
        ProjectRoot = $script:ProjectRoot
        Language    = [string]$script:CurrentLanguage
        State       = @{}
    }
    # Closures capture only simple data and use cmdlets, so they work from any
    # module scope and after the loader function has returned.
    $logRef = @{ Id = [string]$Module.Id; File = [string]$script:DashboardModuleLogFile }
    $langRef = @{ Value = [string]$script:CurrentLanguage }
    $context.Log = ({
        param($message)
        try {
            Add-Content -LiteralPath $logRef.File -Value ('[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}' -f (Get-Date), $logRef.Id, $message) -Encoding UTF8
        } catch { }
    }).GetNewClosure()
    $context.T = ({
        param($zh, $en)
        if ($langRef.Value -eq 'en') { return $en }
        return $zh
    }).GetNewClosure()

    if ($Module.LogicPath) {
        try {
            $probe = Get-Content -LiteralPath $Module.LogicPath -Raw -Encoding UTF8
            if ($probe.Trim()) {
                & {
                    param($moduleContext)
                    . $moduleContext.Module.LogicPath
                    if (Get-Command Initialize-DashboardModule -ErrorAction SilentlyContinue) {
                        Initialize-DashboardModule $moduleContext
                    }
                } $context
            }
        } catch {
            try { [void]$Tabs.Items.Remove($tab) } catch { }
            $result.Error = '逻辑脚本失败：' + $_.Exception.Message
            Write-DashboardModuleLog ('[' + $Module.Id + '] ' + $result.Error + [Environment]::NewLine + $_.ScriptStackTrace)
            return $result
        }
    }

    $tab.Tag = $Module.Id
    $result.Ok = $true
    $result.Tab = $tab
    $script:LoadedDashboardModules[$Module.Id] = @{ Module = $Module; Tab = $tab; Context = $context }
    Write-DashboardModuleLog ('[' + $Module.Id + '] loaded ' + $Module.Version)
    return $result
}

function Unload-DashboardModule {
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)]$Tabs)
    if (-not $script:LoadedDashboardModules.ContainsKey($Id)) { return $false }
    $loaded = $script:LoadedDashboardModules[$Id]
    try { [void]$Tabs.Items.Remove($loaded.Tab) } catch { }
    [void]$script:LoadedDashboardModules.Remove($Id)
    Write-DashboardModuleLog ('[' + $Id + '] unloaded')
    return $true
}

function Set-DashboardModuleEnabled {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [Parameter(Mandatory = $true)]$Tabs,
        [string]$ToolsRoot = ''
    )

    $state = Read-DashboardModuleState
    $disabled = @($state.disabled | Where-Object { $_ -ne $Id })
    if (-not $Enabled) { $disabled += $Id }
    $state.disabled = @($disabled | Select-Object -Unique)
    Save-DashboardModuleState $state

    if (-not $Enabled) {
        Unload-DashboardModule -Id $Id -Tabs $Tabs | Out-Null
        return [pscustomobject]@{ Ok = $true; Loaded = $false; Error = '' }
    }

    $scan = Get-DashboardModules -ToolsRoot $ToolsRoot
    $module = $scan.Modules | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $module) { return [pscustomobject]@{ Ok = $false; Loaded = $false; Error = '模块不存在' } }
    if ($script:LoadedDashboardModules.ContainsKey($Id)) {
        return [pscustomobject]@{ Ok = $true; Loaded = $true; Error = '' }
    }
    $import = Import-DashboardModule -Module $module -Tabs $Tabs -ToolsRoot $ToolsRoot
    return [pscustomobject]@{ Ok = $import.Ok; Loaded = $import.Ok; Error = $import.Error }
}

function Initialize-DashboardModules {
    param(
        [Parameter(Mandatory = $true)]$Tabs,
        [string]$ToolsRoot = ''
    )
    $scan = Get-DashboardModules -ToolsRoot $ToolsRoot
    $loaded = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList
    foreach ($module in $scan.Modules) {
        if (-not $module.Enabled) { continue }
        $import = Import-DashboardModule -Module $module -Tabs $Tabs -ToolsRoot $ToolsRoot
        if ($import.Ok) {
            [void]$loaded.Add($import)
        } else {
            [void]$failed.Add($import)
        }
    }
    return [pscustomobject]@{
        Root   = $scan.Root
        Total  = @($scan.Modules).Count
        Loaded = @($loaded)
        Failed = @($failed)
    }
}

function Register-DashboardModuleExceptionHook {
    param([Parameter(Mandatory = $true)]$Window)
    if ($script:DashboardModuleExceptionHook) { return }
    $script:DashboardModuleExceptionHook = $true
    try {
        $Window.Dispatcher.Add_UnhandledException({
            $exception = $null
            try { $exception = $args[1].Exception } catch { }
            try { $args[1].Handled = $true } catch { }
            $message = if ($exception) { $exception.Message } else { '未知错误' }
            Write-DashboardModuleLog ('unhandled dispatcher exception: ' + $message + [Environment]::NewLine + [string]$exception)
            try {
                [Windows.MessageBox]::Show(
                    ('控制台模块运行出错，已被拦截，主控台继续运行。' + [Environment]::NewLine + [Environment]::NewLine + $message),
                    '模块运行错误', 'OK', 'Error') | Out-Null
            } catch { }
        }) | Out-Null
    } catch {
        $script:DashboardModuleExceptionHook = $false
        Write-DashboardModuleLog ('failed to register dispatcher hook: ' + $_.Exception.Message)
    }
}
