# Usage: scoop update <app> [options]
# Summary: Update apps, or Scoop itself
# Help: 'scoop update' updates Scoop to the latest version.
# 'scoop update <app>' installs a new version of that app, if there is one.
#
# You can use '*' in place of <app> to update all apps.
#
# Options:
#   --global, -g    update a globally installed app
#   --force, -f     force update even when there isn't a newer version
#   --no-cache, -k  don't use the download cache
#   --quiet, -q     hide extraneous messages
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\decompress.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\config.ps1"

reset_aliases

$update_restart = [int]$env:SCOOP__updateRestart
$args_initial = $args

$opt, $apps, $err = getopt $args 'gfkq' 'global','force', 'no-cache', 'quiet'
if($err) { "scoop update: $err"; exit 1 }
$global = $opt.g -or $opt.global
$force = $opt.f -or $opt.force
$use_cache = !($opt.k -or $opt.'no-cache')
$quiet = $opt.q -or $opt.quiet

function update_scoop() {
    # check for git
    $git = try { gcm git -ea stop } catch { $null }
    if(!$git) { abort "scoop uses git to update itself. run 'scoop install git'." }

    $update_commit_target = 'FETCH_HEAD'  # or, for a complete reset, use "origin/HEAD"

    "updating scoop..."
    $currentdir = fullpath $(versiondir 'scoop' 'current')
    $hash_original = ""
    if(!(test-path "$currentdir\.git")) {
        # load config
        $repo = $(scoop config SCOOP_REPO)
        if(!$repo) {
            $repo = "http://github.com/lukesampson/scoop"
            scoop config SCOOP_REPO "$repo"
        }

        $branch = $(scoop config SCOOP_BRANCH)
        if(!$branch) {
            $branch = "master"
            scoop config SCOOP_BRANCH "$branch"
        }

        # remove non-git scoop
        rm -r -force $currentdir -ea stop

        # get git scoop
        git clone -q $repo --branch $branch --single-branch $currentdir
    }
    else {
        pushd $currentdir
        $hash_original = git describe --all --long
        git fetch --quiet
        git reset --quiet --hard $update_commit_target
        git clean -fd
        popd
    }
    pushd $currentdir
    $hash_new = git describe --all --long
    popd
    if ( $hash_new -ne $hash_original ) {
        $max_restarts = 1
        if ( $update_restart -gt $max_restarts ) {
            warn "scoop code was changed, please re-run 'scoop update'"
        }
        else {
            write-host "scoop code was changed, restarting update..."
            & "$psscriptroot\..\bin\scoop.ps1" update -__updateRestart $($update_restart + 1) $args_initial
            exit $lastExitCode
        }
    }

    ensure_scoop_in_path $false
    shim "$currentdir\bin\scoop.ps1" $false

    @(buckets) | % {
        "updating $_ bucket..."
        pushd (bucketdir $_)
        git fetch --quiet
        git reset --quiet --hard $update_commit_target
        git clean -fd
        popd
    }
    success 'scoop was updated successfully!'
}

function update($app, $global, $quiet = $false) {
    $old_version = current_version $app $global
    $old_manifest = installed_manifest $app $old_version $global
    $install = install_info $app $old_version $global
    $check_hash = $true

    # re-use architecture, bucket and url from first install
    $architecture = $install.architecture
    $bucket = $install.bucket
    $url = $install.url

    # check dependencies
    $deps = @(deps $app $architecture) | ? { !(installed $_) }
    $deps | % { install_app $_ $architecture $global }

    $version = latest_version $app $bucket $url
    $is_nightly = $version -eq 'nightly'
    if($is_nightly) {
        $version = nightly_version $(get-date) $quiet
        $check_hash = $false
    }

    if(!$force -and ($old_version -eq $version)) {
        if (!$quiet) {
            warn "the latest version of $app ($version) is already installed."
            "run 'scoop update' to check for new versions."
        }
        return
    }
    if(!$version) { abort "no manifest available for $app" } # installed from a custom bucket/no longer supported

    $manifest = manifest $app $bucket $url

    "updating $app ($old_version -> $version)"

    $dir = versiondir $app $old_version $global

    "uninstalling $app ($old_version)"
    run_uninstaller $old_manifest $architecture $dir
    rm_shims $old_manifest $global
    env_rm_path $old_manifest $dir $global
    env_rm $old_manifest $global
    # note: keep the old dir in case it contains user files

    "installing $app ($version)"
    $dir = ensure (versiondir $app $version $global)

    # save info for uninstall
    save_installed_manifest $app $bucket $dir $url
    save_install_info @{ 'architecture' = $architecture; 'url' = $url; 'bucket' = $bucket } $dir

    $fname = dl_urls $app $version $manifest $architecture $dir $use_cache $check_hash
    unpack_inno $fname $manifest $dir
    pre_install $manifest
    run_installer $fname $manifest $architecture $dir
    ensure_install_dir_not_in_path $dir
    create_shims $manifest $dir $global
    env_add_path $manifest $dir $global
    env_set $manifest $dir $global
    post_install $manifest

    success "$app was updated from $old_version to $version"

    show_notes $manifest
}

function ensure_all_installed($apps, $global) {
    $app = $apps | ? { !(installed $_ $global) } | select -first 1 # just get the first one that's not installed
    if($app) {
        if(installed $app (!$global)) {
            function wh($g) { if($g) { "globally" } else { "for your account" } }
            write-host "$app isn't installed $(wh $global), but it is installed $(wh (!$global))" -f darkred
            "try updating $(if($global) { 'without' } else { 'with' }) the --global (or -g) flag instead"
            exit 1
        } else {
            abort "$app isn't installed"
        }
    }
}

# convert list of apps to list of ($app, $global) tuples
function applist($apps, $global) {
    return ,@($apps |% { ,@($_, $global) })
}

if(!$apps) {
    if($global) {
        "scoop update: --global is invalid when <app> not specified"; exit 1
    }
    if (!$use_cache) {
        "scoop update: --no-cache is invalid when <app> not specified"; exit 1
    }
    update_scoop
} else {
    if($global -and !(is_admin)) {
        'ERROR: you need admin rights to update global apps'; exit 1
    }

    if($apps -eq '*') {
        $apps = applist (installed_apps $false) $false
        if($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        ensure_all_installed $apps $global
        $apps = applist $apps $global
    }

    # $apps is now a list of ($app, $global) tuples
    $apps | % { update @_ $quiet }
}

exit 0
