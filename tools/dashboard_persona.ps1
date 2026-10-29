#Requires -Version 5.1
<#
Persona manager backend for the dashboard.

All reads and writes go through the local AstrBot API, so the dashboard never
needs to write AstrBot/data from the interactive account (which is blocked by
the data-directory ACL). Switching the active persona updates
agent_runner.config.persona.persona_id in the system config; AstrBot's config
service reloads the pipeline after the save.
#>

function Get-AstrBotPersonaList {
    $response = Invoke-AstrBotApi -Method GET -ApiPath '/api/persona/list'
    if (-not $response -or $response.status -eq 'error') { throw ('persona list failed: ' + [string]$response.message) }
    return @($response.data)
}

function Get-AstrBotPersonaDetail {
    param([Parameter(Mandatory = $true)][string]$PersonaId)
    $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/persona/detail' -Body @{ persona_id = $PersonaId }
    if (-not $response -or $response.status -eq 'error') { throw ('persona detail failed: ' + [string]$response.message) }
    return $response.data
}

function Get-AstrBotActivePersona {
    $response = Invoke-AstrBotApi -Method GET -ApiPath '/api/v1/system-config'
    if (-not $response -or $response.status -eq 'error') { throw ('system config read failed: ' + [string]$response.message) }
    $config = $response.data.config
    try { return [string]$config.agent_runner.config.persona.persona_id } catch { return '' }
}

function Set-AstrBotActivePersona {
    param([Parameter(Mandatory = $true)][string]$PersonaId)
    $response = Invoke-AstrBotApi -Method GET -ApiPath '/api/v1/system-config'
    if (-not $response -or $response.status -eq 'error') { throw ('system config read failed: ' + [string]$response.message) }
    $config = $response.data.config
    if (-not $config.agent_runner) { $config | Add-Member -NotePropertyName agent_runner -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $config.agent_runner.config) { $config.agent_runner | Add-Member -NotePropertyName config -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $config.agent_runner.config.persona) { $config.agent_runner.config | Add-Member -NotePropertyName persona -NotePropertyValue ([pscustomobject]@{}) -Force }
    $config.agent_runner.config.persona.persona_id = $PersonaId
    $save = Invoke-AstrBotApi -Method PUT -ApiPath '/api/v1/system-config' -Body $config
    if (-not $save -or $save.status -eq 'error') { throw ('system config save failed: ' + [string]$save.message) }
    return [string]$save.message
}

function Backup-AstrBotPersona {
    param(
        [Parameter(Mandatory = $true)][string]$PersonaId,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )
    $detail = Get-AstrBotPersonaDetail $PersonaId
    $dir = Join-Path $ProjectRoot 'backups\personas'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $safe = ($PersonaId -replace '[^\w\u4e00-\u9fa5.-]', '_')
    $path = Join-Path $dir ($safe + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    $detail | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function New-AstrBotPersona {
    param(
        [Parameter(Mandatory = $true)][string]$PersonaId,
        [Parameter(Mandatory = $true)][string]$SystemPrompt
    )
    if ($PersonaId -notmatch '^[^\s\\/:*?"<>|]{1,64}$') { throw 'invalid persona id' }
    if (-not $SystemPrompt.Trim()) { throw 'system prompt is empty' }
    $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/persona/create' -Body @{
        persona_id    = $PersonaId
        system_prompt = $SystemPrompt
    }
    if (-not $response -or $response.status -eq 'error') { throw ('persona create failed: ' + [string]$response.message) }
    return $response.data
}

function Copy-AstrBotPersona {
    param(
        [Parameter(Mandatory = $true)][string]$SourceId,
        [Parameter(Mandatory = $true)][string]$PersonaId
    )
    $detail = Get-AstrBotPersonaDetail $SourceId
    $prompt = [string]$detail.system_prompt
    if (-not $prompt) { throw 'source persona has an empty prompt' }
    return New-AstrBotPersona -PersonaId $PersonaId -SystemPrompt $prompt
}

function Remove-AstrBotPersona {
    param(
        [Parameter(Mandatory = $true)][string]$PersonaId,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )
    if ($PersonaId -eq 'default') { throw 'the default persona cannot be deleted' }
    $backup = Backup-AstrBotPersona -PersonaId $PersonaId -ProjectRoot $ProjectRoot
    $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/persona/delete' -Body @{ persona_id = $PersonaId }
    if (-not $response -or $response.status -eq 'error') { throw ('persona delete failed: ' + [string]$response.message) }
    return [pscustomobject]@{ Backup = $backup; Message = [string]$response.message }
}
