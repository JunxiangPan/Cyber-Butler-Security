#Requires -Version 5.1
<#
Persona manager backend for the dashboard.

All reads and writes go through the local AgentRuntime API, so the dashboard never
needs to write AgentRuntime/data from the interactive account (which is blocked by
the data-directory ACL). Switching the active persona updates
agent_runner.config.persona.persona_id in the system config; AgentRuntime's config
service reloads the pipeline after the save.
#>

function Get-AgentRuntimePersonaList {
    $response = Invoke-AgentRuntimeApi -Method GET -ApiPath '/api/persona/list'
    if (-not $response -or $response.status -eq 'error') { throw ('persona list failed: ' + [string]$response.message) }
    return @($response.data)
}

function Get-AgentRuntimePersonaDetail {
    param([Parameter(Mandatory = $true)][string]$PersonaId)
    $response = Invoke-AgentRuntimeApi -Method POST -ApiPath '/api/persona/detail' -Body @{ persona_id = $PersonaId }
    if (-not $response -or $response.status -eq 'error') { throw ('persona detail failed: ' + [string]$response.message) }
    return $response.data
}

function Get-AgentRuntimeActivePersona {
    $response = Invoke-AgentRuntimeApi -Method GET -ApiPath '/api/v1/system-config'
    if (-not $response -or $response.status -eq 'error') { throw ('system config read failed: ' + [string]$response.message) }
    $config = $response.data.config
    try { return [string]$config.agent_runner.config.persona.persona_id } catch { return '' }
}

function Set-AgentRuntimeActivePersona {
    param([Parameter(Mandatory = $true)][string]$PersonaId)
    $response = Invoke-AgentRuntimeApi -Method GET -ApiPath '/api/v1/system-config'
    if (-not $response -or $response.status -eq 'error') { throw ('system config read failed: ' + [string]$response.message) }
    $config = $response.data.config
    if (-not $config.agent_runner) { $config | Add-Member -NotePropertyName agent_runner -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $config.agent_runner.config) { $config.agent_runner | Add-Member -NotePropertyName config -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $config.agent_runner.config.persona) { $config.agent_runner.config | Add-Member -NotePropertyName persona -NotePropertyValue ([pscustomobject]@{}) -Force }
    $config.agent_runner.config.persona.persona_id = $PersonaId
    $save = Invoke-AgentRuntimeApi -Method PUT -ApiPath '/api/v1/system-config' -Body $config
    if (-not $save -or $save.status -eq 'error') { throw ('system config save failed: ' + [string]$save.message) }
    return [string]$save.message
}

function Backup-AgentRuntimePersona {
    param(
        [Parameter(Mandatory = $true)][string]$PersonaId,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )
    $detail = Get-AgentRuntimePersonaDetail $PersonaId
    $dir = Join-Path $ProjectRoot 'backups\personas'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $safe = ($PersonaId -replace '[^\w\u4e00-\u9fa5.-]', '_')
    $path = Join-Path $dir ($safe + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    $detail | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function New-AgentRuntimePersona {
    param(
        [Parameter(Mandatory = $true)][string]$PersonaId,
        [Parameter(Mandatory = $true)][string]$SystemPrompt
    )
    if ($PersonaId -notmatch '^[^\s\\/:*?"<>|]{1,64}$') { throw 'invalid persona id' }
    if (-not $SystemPrompt.Trim()) { throw 'system prompt is empty' }
    $response = Invoke-AgentRuntimeApi -Method POST -ApiPath '/api/persona/create' -Body @{
        persona_id    = $PersonaId
        system_prompt = $SystemPrompt
    }
    if (-not $response -or $response.status -eq 'error') { throw ('persona create failed: ' + [string]$response.message) }
    return $response.data
}

function Copy-AgentRuntimePersona {
    param(
        [Parameter(Mandatory = $true)][string]$SourceId,
        [Parameter(Mandatory = $true)][string]$PersonaId
    )
    $detail = Get-AgentRuntimePersonaDetail $SourceId
    $prompt = [string]$detail.system_prompt
    if (-not $prompt) { throw 'source persona has an empty prompt' }
    return New-AgentRuntimePersona -PersonaId $PersonaId -SystemPrompt $prompt
}

function Remove-AgentRuntimePersona {
    param(
        [Parameter(Mandatory = $true)][string]$PersonaId,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )
    if ($PersonaId -eq 'default') { throw 'the default persona cannot be deleted' }
    $backup = Backup-AgentRuntimePersona -PersonaId $PersonaId -ProjectRoot $ProjectRoot
    $response = Invoke-AgentRuntimeApi -Method POST -ApiPath '/api/persona/delete' -Body @{ persona_id = $PersonaId }
    if (-not $response -or $response.status -eq 'error') { throw ('persona delete failed: ' + [string]$response.message) }
    return [pscustomobject]@{ Backup = $backup; Message = [string]$response.message }
}
