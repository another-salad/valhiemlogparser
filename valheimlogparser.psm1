# Hideous hackery with the regexes really, we will look for a _unique_ group name to infer which object to shove back into the pipe.
$JoinRegex  = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): (?<JoinPhrase>Got character ZDOID from) (?<PlayerName>.*) : (?<PlayerId>-?\d+):(?<PlayerIndex>\d+)"
$LeaveRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): (?<LeavePhrase>Destroying abandoned non persistent zdo) (?<PlayerId>-?\d+):(?<PlayerIndex>\d+) owner -?\d+"
$DeathRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): (?<DeathPhrase>Got character ZDOID from) (?<PlayerName>.*) : 0:0"

# Will do a 'one shot' (sure why not) read of the server log, parsing it with all of the above regexes.
# It should be then trival for any callers to filter out what they want.
Function Read-ServerLog {
    [cmdletbinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][ValidateScript({test-path $_ -PathType Leaf})][string]$logFile)
    process {
        Select-String -Path $logFile -Pattern "$joinregex|$LeaveRegex|$DeathRegex" | % {
            $m = $_.Matches[0]
            if ($m.Groups['JoinPhrase'].Success) {
                $PlayerEvent = [pscustomobject]@{
                    PsTypeName = "PlayerJoin"
                    Name       = $m.Groups['PlayerName'].Value
                    Id         = $m.Groups['PlayerId'].Value
                    Index      = $m.Groups['PlayerIndex'].Value
                }
            } elseif ($m.Groups['LeavePhrase'].Success) {
                $PlayerEvent = [pscustomobject]@{
                    PsTypeName = "PlayerLeave"
                    Id         = $m.Groups['PlayerId'].Value
                    Index      = $m.Groups['PlayerIndex'].Value
                }
            # Logically must be death due to the regexes passed in (and the fact we have a hit), but lets be explicit.
            } elseif ($m.Groups['DeathPhrase'].Success) {
                $PlayerEvent = [pscustomobject]@{
                    PsTypeName = "PlayerDeath"
                    Name       = $m.Groups['PlayerName'].Value
                }
            }
            $PlayerEvent | Add-Member -MemberType NoteProperty -Name Date -Value ([datetime]$m.Groups['Date'].Value)
            $PlayerEvent | Add-Member -MemberType NoteProperty -Name RawLine -Value $_.Line
            $PlayerEvent | Add-Member -MemberType NoteProperty -Name LineNumber -Value $_.LineNumber -PassThru
        }
    }
}


Function Get-PlayerLogin {
    [cmdletbinding(DefaultParameterSetName="LogFile")]
    param(
        [Parameter(ParameterSetName="LogFile",ValueFromPipeline,Mandatory)][string]$logFile,
        [Parameter(ParameterSetName="ServerEvent",ValueFromPipeline,Mandatory)][Pscustomobject[]]$ServerEvent
    )
    # Gets the latest login event for a player from the server log
    process {
        $(if ($logFile) {$logfile | Read-ServerLog } else {$ServerEvent}) | where {$_.Psobject.Typenames -contains "PlayerJoin"}
    }
}

Function Get-LatestPlayerLogin {
    [cmdletbinding(DefaultParameterSetName="LogFile")]
    param(
        [Parameter(ParameterSetName="LogFile",ValueFromPipeline,Mandatory)][string]$logFile,
        [Parameter(ParameterSetName="ServerEvent",ValueFromPipeline,Mandatory)][Pscustomobject[]]$ServerEvent
    )
    end {
        $(if($input.GetType() -eq [string]) {$input | Read-ServerLog} else {$input}) | Get-PlayerLogin | Sort-Object -Property LineNumber -Descending | Sort-Object -Property Name -Unique
    }
}


Function Get-ActivePlayer {
    [cmdletbinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][string]$logFile)
    process {
        $allEvents = $logfile | Read-ServerLog
        $LogoutEvents = $allEvents | ? {$_.Psobject.Typenames -contains "PlayerLeave"} | Sort-Object -Property LineNumber -Descending | Sort-Object -Property Id -Unique
        # Current active users
        # Players may have logged in and out throughout the day, so we only care about logout events that have happened after the latest login.
        $allEvents | Get-PlayerLogin | ? {$_.id -notin $LogoutEvents.Id}
    }
}

Function Get-PlayerDeath {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][string]$logFile)
    process {
        $logfile | Read-ServerLog | ? {$_.Psobject.Typenames -contains "PlayerDeath"}
    }
}

Function Get-Player {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][string]$logFile)
    process {
        $allEvents = $logfile | Read-ServerLog
        $LogoutEvents = $allEvents | ? {$_.Psobject.Typenames -contains "PlayerLeave"} | Sort-Object -Property LineNumber -Descending | Sort-Object -Property Id -Unique
        $allEvents | Get-LatestPlayerLogin | % {
            $Login = $_
            $logout = $LogoutEvents | ? { $_.Id -eq $login.Id } | select -First 1
            if ($logout) {
                $login | Add-Member -MemberType NoteProperty -Name LoggedOut -Value $logout.Date
            }
            $Login
        }
    }
}
