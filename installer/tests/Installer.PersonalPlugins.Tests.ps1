$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.PersonalPlugins.ps1')

$script:CbsNames = @(
    'astrbot_plugin_at_gate','astrbot_plugin_cloud_fallback','astrbot_plugin_dsh_bridge',
    'astrbot_plugin_dst_guard','astrbot_plugin_mcp_readonly','astrbot_plugin_router',
    'astrbot_plugin_security_gate','astrbot_plugin_totp_broker','astrbot_plugin_weather_tools',
    'astrbot_plugin_webui_bridge'
)
$script:PersonalNames = @('astrbot_plugin_private_companion','astrbot_plugin_livingmemory','astrbot_plugin_memorix')

function New-PluginSource {
    param([string]$Root, [string]$Name, [string]$Code, [string]$Schema = '')
    $path = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $path 'main.py') -Value $Code -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $path 'metadata.yaml') -Value ('name: ' + $Name) -Encoding UTF8
    if ($Schema) { Set-Content -LiteralPath (Join-Path $path '_conf_schema.json') -Value $Schema -Encoding UTF8 }
    return $path
}

Describe 'Installer personal plugins' {
    It 'copies CBS plugins and updates their schema' {
        $base = Join-Path $env:TEMP ('cb-plugins-' + [guid]::NewGuid().ToString('N'))
        $release = Join-Path $base 'release-plugins'
        $astrbot = Join-Path $base 'ExternalAgent'
        try {
            foreach ($name in $script:CbsNames) { New-PluginSource -Root $release -Name $name -Code 'v1' -Schema '{"schema":1}' | Out-Null }
            $result = Copy-CyberButlerCbsPlugins -ExternalAgentPath $astrbot -ReleasePluginsPath $release
            $result.status | Should Be 'installed'
            @($result.plugins).Count | Should Be 10
            foreach ($name in $script:CbsNames) {
                (Test-Path -LiteralPath (Join-Path $astrbot ('data\plugins\' + $name + '\main.py'))) | Should Be $true
            }
            $schema = Join-Path $astrbot 'data\plugins\astrbot_plugin_router\_conf_schema.json'
            Set-Content -LiteralPath (Join-Path $release 'astrbot_plugin_router\main.py') -Value 'v2' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $release 'astrbot_plugin_router\_conf_schema.json') -Value '{"schema":2}' -Encoding UTF8
            $second = Copy-CyberButlerCbsPlugins -ExternalAgentPath $astrbot -ReleasePluginsPath $release
            (Get-Content -LiteralPath $schema -Raw).Trim() | Should Be '{"schema":2}'
            (Get-Content -LiteralPath (Join-Path $astrbot 'data\plugins\astrbot_plugin_router\main.py') -Raw).Trim() | Should Be 'v2'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'copies personal plugins while preserving data and schema' {
        $base = Join-Path $env:TEMP ('cb-plugins-' + [guid]::NewGuid().ToString('N'))
        $personal = Join-Path $base 'personal'
        $astrbot = Join-Path $base 'ExternalAgent'
        try {
            foreach ($name in $script:PersonalNames) { New-PluginSource -Root $personal -Name $name -Code 'new-code' -Schema '{"source":1}' | Out-Null }
            $target = Join-Path $astrbot 'data\plugins\astrbot_plugin_private_companion'
            New-Item -ItemType Directory -Path (Join-Path $target 'data') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'data\memory.db') -Value 'keep-data' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $target '_conf_schema.json') -Value '{"user":1}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $target 'main.py') -Value 'old-code' -Encoding UTF8
            $result = Copy-CyberButlerPersonalPlugins -ExternalAgentPath $astrbot -PersonalPluginsPath $personal
            $result.status | Should Be 'updated'
            (Get-Content -LiteralPath (Join-Path $target 'main.py') -Raw).Trim() | Should Be 'new-code'
            (Get-Content -LiteralPath (Join-Path $target 'data\memory.db') -Raw).Trim() | Should Be 'keep-data'
            (Get-Content -LiteralPath (Join-Path $target '_conf_schema.json') -Raw).Trim() | Should Be '{"user":1}'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'ignores an unknown plugin and does not copy it' {
        $base = Join-Path $env:TEMP ('cb-plugins-' + [guid]::NewGuid().ToString('N'))
        $personal = Join-Path $base 'personal'
        $astrbot = Join-Path $base 'ExternalAgent'
        try {
            foreach ($name in $script:PersonalNames) { New-PluginSource -Root $personal -Name $name -Code 'x' | Out-Null }
            New-PluginSource -Root $personal -Name 'astrbot_plugin_router' -Code 'bad' | Out-Null
            $output = & { Copy-CyberButlerPersonalPlugins -ExternalAgentPath $astrbot -PersonalPluginsPath $personal } 6>&1
            (($output | ForEach-Object { [string]$_ }) -join "`n") | Should Match 'WARN ignored non-personal plugin: astrbot_plugin_router'
            (Test-Path -LiteralPath (Join-Path $astrbot 'data\plugins\astrbot_plugin_router')) | Should Be $false
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'preserves files in repair mode' {
        $base = Join-Path $env:TEMP ('cb-plugins-' + [guid]::NewGuid().ToString('N'))
        $personal = Join-Path $base 'personal'
        $astrbot = Join-Path $base 'ExternalAgent'
        try {
            foreach ($name in $script:PersonalNames) {
                New-PluginSource -Root $personal -Name $name -Code 'new' | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $astrbot ('data\plugins\' + $name)) -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $astrbot ('data\plugins\' + $name + '\main.py')) -Value 'old' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path (Join-Path (Join-Path $astrbot 'data\plugins') $name) 'metadata.yaml') -Value 'old' -Encoding UTF8
            }
            $result = Copy-CyberButlerPersonalPlugins -ExternalAgentPath $astrbot -PersonalPluginsPath $personal -Repair
            $result.status | Should Be 'preserved'
            (Get-Content -LiteralPath (Join-Path $astrbot 'data\plugins\astrbot_plugin_private_companion\main.py') -Raw).Trim() | Should Be 'old'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'fails repair when target metadata.yaml is missing' {
        $base = Join-Path $env:TEMP ('cb-plugins-' + [guid]::NewGuid().ToString('N'))
        $personal = Join-Path $base 'personal'
        $astrbot = Join-Path $base 'ExternalAgent'
        try {
            foreach ($name in $script:PersonalNames) {
                New-PluginSource -Root $personal -Name $name -Code 'new' | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $astrbot ('data\plugins' + $name)) -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $astrbot ('data\plugins' + $name + '\main.py')) -Value 'old' -Encoding UTF8
            }
            { Copy-CyberButlerPersonalPlugins -ExternalAgentPath $astrbot -PersonalPluginsPath $personal -Repair } | Should Throw
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'is idempotent and does not create .bak files' {
        $base = Join-Path $env:TEMP ('cb-plugins-' + [guid]::NewGuid().ToString('N'))
        $personal = Join-Path $base 'personal'
        $astrbot = Join-Path $base 'ExternalAgent'
        try {
            foreach ($name in $script:PersonalNames) { New-PluginSource -Root $personal -Name $name -Code 'same' | Out-Null }
            $first = Copy-CyberButlerPersonalPlugins -ExternalAgentPath $astrbot -PersonalPluginsPath $personal
            $second = Copy-CyberButlerPersonalPlugins -ExternalAgentPath $astrbot -PersonalPluginsPath $personal
            @($second.plugins | Where-Object { $_.status -eq 'preserved' }).Count | Should Be 3
            @(Get-ChildItem -LiteralPath $astrbot -Recurse -Filter '*.bak' -ErrorAction SilentlyContinue).Count | Should Be 0
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }
}
