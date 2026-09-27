$JoinRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): Got character ZDOID from (?<PlayerName>.*) : (?<PlayerId>-?\d+):(?<PlayerIndex>\d+)"
$LeaveRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): Destroying abandoned non persistent zdo (?<PlayerId>-?\d+):(?<PlayerIndex>\d+) owner -?\d+"
$DeathRegex = "(?<Date>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}): Got character ZDOID from (?<PlayerName>.*) : 0:0"

Function Get-PlayerLogin {
    [cmdletbinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][ValidateScript({test-path $_ -PathType Leaf})][string]$logFile)
    # Gets the latest login event for a player from the server log
    process {
        Select-String -Path $logFile -Pattern $joinregex | % {
            $m = $_.Matches[0]
            [pscustomobject]@{
                PsTypeName = "PlayerJoin"
                Name       = $m.Groups['PlayerName'].Value
                Date       = $m.Groups['Date'].Value
                Id         = $m.Groups['PlayerId'].Value
                Index      = $m.Groups['PlayerIndex'].Value
                RawLine    = $_.Line
                LineNumber = $_.LineNumber
            }
        # This is a spawny deathy thing, not a real login
        } | where RawLine -notmatch "Got character ZDOID from (?<PlayerName>.*) : 0:0"
    }
}

Function Get-LatestPlayerLogin {
    [cmdletbinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][ValidateScript({test-path $_ -PathType Leaf})][string]$logFile)
    process {
        # Gets the latest login event for a player from the server log
        $logFile | Get-PlayerLogin | Sort-Object -Property LineNumber -Descending | Sort-Object -Property Name -Unique
    }
}


Function Get-ActivePlayer {
    [cmdletbinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][ValidateScript({test-path $_ -PathType Leaf})][string]$logFile)
    process {
        # NOTE(AnotherSalad): I know what you are thinking, boi is he reading that log file a lot.
        # So, I had thought about just get-contenting up the file and feeding it into select-string.
        # Select-string with the -inputobject param was not behaving in a way that seemed sane when attempting to pass the
        # entire file into it.
        # I could pipeline it, and that was working nicely, however in a pipe we lose content of the entire file, i.e. line numbers.
        # Line numbers are important here, as it gives us the context of when an event happened, relative to others. Using time is brittle,
        # (yes, this whole thing is, as its log parsing, but this is the world we live in), I didn't fancy getting confused by the container/server
        # changing time whilst things are running, and the old classic, day light savings.
        # I spent some time trying to think of a nice way of only reading the file once and still keeping context, but I realised that:
        # A) these log files aren't huge fam
        # B) I'm likely to make something even more brittle in an attempt to avoid a problem that doesn't actually exist
        # So, here we are, reading the file for each select-string. Soz?
        # Now get the latest logout event for each player (may not have happened yet)
        $LogoutEvents = Select-String -Path $logFile -Pattern $LeaveRegex | % {
            $m = $_.Matches[0]
            [pscustomobject]@{
                PsTypeName = "PlayerLeave"
                Date       = $m.Groups['Date'].Value
                Id         = $m.Groups['PlayerId'].Value
                Index      = $m.Groups['PlayerIndex'].Value
                RawLine    = $_.Line
                LineNumber = $_.LineNumber
            }
        } | Sort-Object -Property LineNumber -Descending | Sort-Object -Property Id -Unique

        # Current active users
        # Players may have logged in and out throughout the day, so we only care about logout events that have happened after the latest login.
        $logFile | Get-LatestPlayerLogin | where {$_.id -notin $LogoutEvents.Id}
    }
}

Function Get-PlayerDeath {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline,Mandatory)][ValidateScript({test-path $_ -PathType Leaf})][string]$logFile)
    process {
        Select-String -Path $logFile -Pattern $DeathRegex | % {
            $m = $_.Matches[0]
            [pscustomobject]@{
                PsTypeName = "PlayerDeath"
                Name       = $m.Groups['PlayerName'].Value
                Date       = [datetime]$m.Groups['Date'].Value
                RawLine    = $_.Line
                LineNumber = $_.LineNumber
            }
        }
    }
}
