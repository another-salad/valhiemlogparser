# Hideous hackery with the regexes really, we will look for a _unique_ group name to infer which object to shove back into the pipe.
$JoinRegex  = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): (?<JoinPhrase>Got character ZDOID from) (?<PlayerName>.*) : (?<PlayerId>-?\d{2,}):(?<PlayerIndex>\d+)"  # PlayerId will always be an int greater than 2 digits
$LeaveRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): (?<LeavePhrase>Destroying abandoned non persistent zdo) (?<PlayerId>-?\d+):(?<PlayerIndex>\d+) owner -?\d+"
$DeathRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): (?<DeathPhrase>Got character ZDOID from) (?<PlayerName>.*) : 0:0"  # death just zeros out the player id and index, for a reason I'm sure.

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
        # so in pwsh 7.6 shoving -Descending into a sort at the end of this pipe seemingly kept the order from the sort on linenumber (which was also descending), so:
        # .. | get-playerlogin | Sort-Object -Property LineNumber -Descending | Sort-Object -Property Name -Unique -Descending (also worked for ID)
        # But this just felt like a bug waiting to happen so I moved to group (which feels like the right answer anyway)
        $(if($input.GetType() -eq [string]) {$input | Read-ServerLog} else {$input}) | Get-PlayerLogin | Sort-Object -Property LineNumber -Descending | Group-Object Name | % {$_.Group[0]}
    }
}


Function Get-ActivePlayer {
    [cmdletbinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][string]$logFile)
    process {
        $allEvents = $logfile | Read-ServerLog
        $LogoutEvents = $allEvents | ? {$_.Psobject.Typenames -contains "PlayerLeave"} | Sort-Object -Property LineNumber -Descending | Group-Object Id | % {$_.Group[0]}
        # Current active users
        # Players may have logged in and out throughout the day, so we only care about logout events that have happened after the latest login.
        $allEvents | Get-LatestPlayerLogin | ? {$_.id -notin $LogoutEvents.Id}
    }
}

Function Get-PlayerDeath {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][string]$logFile)
    process {
        $logfile | Read-ServerLog | ? {$_.Psobject.Typenames -contains "PlayerDeath"}
    }
}

# Shows their latest login, adds their logout time if they have done so. 
Function Get-Player {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][string]$logFile)
    process {
        $allEvents = $logfile | Read-ServerLog
        $LogoutEvents = $allEvents | ? {$_.Psobject.Typenames -contains "PlayerLeave"} | Sort-Object -Property LineNumber -Descending | Group-Object Id | % {$_.Group[0]}
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
