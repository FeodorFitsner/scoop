$scoopdir = $env:SCOOP, "~\appdata\local\scoop" | select-object -first 1
$globaldir = $env:SCOOP_GLOBAL, "$($env:programdata.tolower())\scoop" | select-object -first 1

# projectrootpath will remain $null when core.ps1 is included via the "locationless" initial install script
$projectrootpath = $null
if ($MyInvocation.mycommand.path) { $projectrootpath = $($MyInvocation.mycommand.path | Split-Path | Split-Path) }

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
            import-module $(resolve-path $(rootrelpath 'vendor\Newtonsoft.Json\lib\net20\Newtonsoft.Json.dll'))
        }
        $f_ToObject = { param( $token )
            $type = $token.psobject.TypeNames -imatch "Newtonsoft\..*(JObject|JArray|JProperty|JValue)"
            if (-not $type) { $type = "DEFAULT" }
            #write-host "ToObject::$($token.psobject.TypeNames)::$type::'$($token.name)'"
            switch ( $type )
            {
                "Newtonsoft.Json.Linq.JObject"
                    {
                    #write-host "object::$($token.psobject.TypeNames)::'$($token.name)'=$($token.value)"
                    $children = $token.children() #|? {$_.psobject.TypeNames -imatch "Newtonsoft\..*(JProperty)"}
                    $h = @{}
                    $children | ForEach-Object {
                        #write-host "object/child::$($_.psobject.TypeNames)::'$($_.name)'[$($_.count)]"
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $h[$token.name] = $_.value
                            }
                        else { $h[$_.name] = $(& $f_ToObject $_.first) }
                        }
                    return ,$h
                    }
                "Newtonsoft.Json.Linq.JArray"
                    {
                    #write-host "array::$($token.psobject.TypeNames)::'$($token.name)'=$($token.value)"
                    $a = @()
                    $token | ForEach-Object {
                        #write-host "array/token::$($_.psobject.TypeNames)::'$($_.name)'=$($_.value)"
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $a += , $_.value
                            }
                        else { $a += , $(& $f_ToObject $_) }
                        }
                    return ,$a
                    }
                default
                    {
                    #write-host "default::$($token.psobject.TypeNames)::'$($token.name)'=$($token.value)"
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

function ConvertTo-JsonPoSH2 {
    # ToDO: SO question: How to make this act as ConvertTo-Json pulling all pipeline input in at once instead of unrolling arrays
    # NOTE: `$o = @( ... ); ,@o | ConvertTo-JsonPoSH2` keeps the array intact and is printed correctly; but that's just silly to force obscure usage like that...
    # NOTE: using $input => [{"CliXml":"<Objs Version=\"1.1.0.1\" xmlns=\"http://schemas.microsoft.com/powershell/2004/04\">\r\n  <Obj RefId=\"0\">\r\n    <I32>1</I32>\r\n  </Obj>\r\n</Objs>"}]
    #   ... clogging the true input object with odd cruft which interferes with correct serialization
    [CmdletBinding()]
    param(
        [parameter(mandatory=$True, ValueFromPipeline=$True)][object] $object,
        [parameter(mandatory=$False)][int] $indentation = 4  ## <0 .. no indentation; >=0 set indentation and indented format; default = 4; NOTE: [int]$null => 0
        )
    BEGIN {
        if (-not (Get-Module 'Newtonsoft.Json')) {
            import-module $(resolve-path $(rootrelpath 'vendor\Newtonsoft.Json\lib\net20\Newtonsoft.Json.dll'))
        }
    }
    PROCESS {
        # `[Newtonsoft.Json.JsonConvert]::SerializeObject( $o )`
        # NOTE: indentation == 4 => output equivalent to ConvertTo-Json()
        $sb = New-Object System.Text.StringBuilder
        $sw = New-Object System.IO.StringWriter($sb)
        $writer = New-Object Newtonsoft.Json.JsonTextWriter($sw)
        if ($indentation -ge 0) {
            $writer.Formatting = [Newtonsoft.Json.Formatting]::Indented     ## indented + multiline
            $writer.Indentation = $indentation
        }
        $s = New-Object Newtonsoft.Json.JsonSerializer
        $s.Serialize( $writer, $object )
        $sw.ToString()
    }
    END {}
}
