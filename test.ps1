. .\lib\core.ps1

$failed_count = 0

$o = ConvertFrom-JsonPoSH2 '{a:1}'
if (-not ($o.'a' -eq 1)) { $failed_count = $failed_count + 1 }

if ($failed_count -gt 0) {
    write-host "FAIL: $failed_count test(s) failed" -f red
    exit $failed_count
} else {
    write-host "PASS: All tests succeeded" -f green
}
