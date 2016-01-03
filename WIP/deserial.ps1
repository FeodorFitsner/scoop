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
            import-module $(resolve-path "$psscriptroot\..\..nuget-modules\Newtonsoft.Json\lib\net20\Newtonsoft.Json.dll")
        }
        $f_ToObject = { param( $token )
            $type = $token.psobject.TypeNames -imatch "Newtonsoft\..*(JObject|JArray|JValue)"
            if (-not $type) { $type = "DEFAULT" }
            #write-host "ToObject::$($token.psobject.TypeNames)::$type"
            switch ( $type )
            {
                "Newtonsoft.Json.Linq.JObject"
                    {
                    #write-host "object::$($token.psobject.TypeNames)::$($token.name)=$($token.value)"
                    $children = $token.children() ##|? {$_.psobject.TypeNames -imatch "Newtonsoft\..*(JProperty)"}
                    $h = @{}
                    $token |% {
                        #write-host "object/child::$($_.psobject.TypeNames)::$($_.name)=$($_.value)"
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JProperty)") {
                            #write-host "object/child/value::$($_.psobject.TypeNames)::$($_.name)=$($_.value)"
                            $h[$_.name] = $_.value     ## ToDO: refactor to simplify and remove quoting
                            }
                        else {
                            #write-host "object/child/()::$($_.psobject.TypeNames)::$($_.name)=$($_.value)"
                            $h[$_.name] = $(& $f_ToObject $_)
                            }
                        }
                    return ,$h
                    }
                "Newtonsoft.Json.Linq.JArray"
                    {
                    #write-host "array::$($token.psobject.TypeNames)::$($token.name)=$($token.value)"
                    $a = @()
                    $token |% {
                        #write-host "array/token::$($_.psobject.TypeNames)::$($_.name)=$($_.value)"
                        if ($_.psobject.TypeNames -imatch "Newtonsoft\..*(JValue)") {
                            $a += , $_.value     ## ToDO: refactor to simplify and remove quoting
                            }
                        else { $a += , $(& $f_ToObject $_) }
                        }
                    return ,$a
                    }
                default
                    {
                    #write-host "default::$($token.psobject.TypeNames)::$($token.name)=$($token.value)"
                    return [int]$token.value
                    }
            }
        }
    }
    PROCESS {
        $p = [Newtonsoft.Json.Linq.JToken]::Parse( $json_string )
        # NOTE: ConvertFrom-Json() returns a "PSCustomObject"; avoided here because "PSCustomObject" re-serializes incorrectly
        $o = ,$(& $f_ToObject $p)
        $o  ## returns "System.Array", "System.Collections.Hashtable", or basic type
    }
    END {}
}

function ConvertTo-JsonPoSH2 {
    [CmdletBinding()]
    param(
        [parameter(mandatory=$True, ValueFromPipeline=$True)][object] $object,
        [parameter(mandatory=$False)][int] $indentation = 4  ## <0 .. no indentation; >=0 set indentation and indented format; default = 4; NOTE: [int]$null => 0
        )
    BEGIN {
        if (-not (Get-Module 'Newtonsoft.Json')) {
            import-module $(resolve-path "$psscriptroot\..\..\nuget-modules\Newtonsoft.Json\lib\net20\Newtonsoft.Json.dll")
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
