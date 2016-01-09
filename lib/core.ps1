$scoopdir = $env:SCOOP, "~\appdata\local\scoop" | select-object -first 1
$globaldir = $env:SCOOP_GLOBAL, "$($env:programdata.tolower())\scoop" | select-object -first 1

$projectrootpath = $null
if ($MyInvocation.mycommand.Definition) { $projectrootpath = $($MyInvocation.MyCommand.Definition | Split-Path | Split-Path) }

            Write-Host "Project root path: $projectrootpath"


function rootrelpath($path) { join-path $projectrootpath $path } # relative to project main directory

# # for CLR < 3.0, use "Json.NET" ... see [Json.NET and PowerShell] http://www.one-tab.com/page/qr_U9Z3vTO67fA41CR1nlg @@ https://archive.is/sCncm
# # ref: http://stackoverflow.com/questions/17601528/read-json-object-in-powershell-2-0
# # ref: http://stackoverflow.com/questions/28077854/powershell-2-0-convertfrom-json-and-convertto-json-implementation/29689642#29689642
# # ref: http://stackoverflow.com/questions/27338009/powershell-how-to-convert-system-collections-generic-dictionary-to-pscustomobjec/27338759#27338759

# translated from ref: http://stackoverflow.com/questions/5546142/how-do-i-use-json-net-to-deserialize-into-nested-recursive-dictionary-and-list/19140420#19140420
# ref: [Json.NET] http://www.newtonsoft.com/json ; [Json.NET Blog] http://james.newtonking.com

function ConvertFrom-JsonPoSH2 {
    [CmdletBinding()]
    param(
        [parameter(mandatory=$True, ValueFromPipeline=$True)] [string]$json_string
        )
    BEGIN {
        if (-not (Get-Module 'Newtonsoft.Json')) {
            $modulePath = rootrelpath('vendor\Newtonsoft.Json\lib\net20\Newtonsoft.Json.dll')
            $modulePath = "$modulePath"
            $modulePath
            import-module $modulePath
        }
        $f_ToObject = { param( $token )
            $type = $token.psobject.TypeNames -imatch "Newtonsoft\..*(JObject|JArray|JProperty|JValue)"
            if (-not $type) { $type = "DEFAULT" }
            switch ( $type )
            {
                "Newtonsoft.Json.Linq.JObject"
                    {
                    $children = $token.children() #|? {$_.psobject.TypeNames -imatch "Newtonsoft\..*(JProperty)"}
                    $h = @{}
                    $children | ForEach-Object {
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $h[$token.name] = $_.value
                            }
                        else { $h[$_.name] = $(& $f_ToObject $_.first) }
                        }
                    return ,$h
                    }
                "Newtonsoft.Json.Linq.JArray"
                    {
                    $a = @()
                    $token | ForEach-Object {
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $a += , $_.value
                            }
                        else { $a += , $(& $f_ToObject $_) }
                        }
                    return ,$a
                    }
                default
                    {
                    return $token.value
                    }
            }
        }
    }
    PROCESS {
        $p = [Newtonsoft.Json.Linq.JToken]::Parse( $json_string )
        # NOTE: ConvertFrom-Json() returns a "PSCustomObject"; avoided here because "PSCustomObject" re-serializes incorrectly
        $o = ,$(& $f_ToObject $p)
        [object]$o  ## returns "System.Array", "System.Collections.Hashtable", or basic type
    }
    END {}
}
