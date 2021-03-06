# Usage: scoop which <command>
# Summary: Locate a program path
# Help: Finds the path to a program that was installed with Scoop
param($command)
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\help.ps1"

reset_aliases

if(!$command) { 'ERROR: <command> missing'; my_usage; exit 1 }

$gcm = try { get-command "$command.ps1" -ea stop } catch { $null }
if(!$gcm) { [console]::error.writeline("'$command' not found"); exit 3 }

$path = "$($gcm.path)"
$usershims = "$(resolve-path $(shimdir $false))"
$globalshims = fullpath (shimdir $true) # don't resolve: may not exist

if($path -like "$usershims*" -or $path -like "$globalshims*") {
    $shimtext = get-content $path
    # $exepath = ($shimtext | where-object { $_.startswith('$path') }).split(' ') `
    #     | select-object -Last 1 | invoke-expression
    $exepath = & $([ScriptBlock]::Create( $(($shimtext | where-object { $_.startswith('$path') }).split(' ') | select-object -Last 1) ))

    if (![system.io.path]::ispathrooted($exepath)) {
        $exepath = resolve-path (join-path (split-path $path) $exepath)
    }

    friendly_path $exepath
} elseif($gcm.commandtype -eq 'Alias') {
    scoop which $gcm.resolvedcommandname
} else {
    [console]::error.writeline("not a scoop shim")
    $path
    exit 2
}

exit 0
