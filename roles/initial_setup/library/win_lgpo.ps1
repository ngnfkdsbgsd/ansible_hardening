#!powershell

# Copyright: (c) 2015, Corwin Brown <corwin.brown@maxpoint.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#Requires -Module Ansible.ModuleUtils.Legacy

$params = Parse-Args $args

$exec_path = Get-AnsibleParam -obj $params -name "exec_path" -type "path" -failifempty $true
$command = Get-AnsibleParam -obj $params -name "command" -type "str" -failifempty $true -ValidateSet "import_from_backup", "import_machine", "import_user", "import_admin", "import_non_admin", "import_audit_pol", "import_sec_pol"
$argv = Get-AnsibleParam -obj $params -name "argv" -type "list" -failifempty $true

$result = @{
    success = $false
    command = $command
    argv = $argv
}

#region guard
    if (-not (Test-Path -Path $exec_path)) {
        Fail-Json $result "could not find lgpo executable at '$exec_path'!"
    }
    if ($argv[0] -eq "") {
        Fail-Json $result "'argv' list parameter is empty!"   
    }
    elseif ($argv.Count -gt 2) {
        Fail-Json $result "'argv' list parameter has too many members (max. 2)!"
    }
#endregion

#region constants
    $pinfo = [System.Diagnostics.ProcessStartInfo]::new()
    $pinfo.FileName = $exec_path
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.CreateNoWindow = $true
    $pinfo.UseShellExecute = $false
    $pinfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $proc = New-Object System.Diagnostics.Process

    $gpo_base_path = "$($env:windir)\system32"
    $import_mappings = @{
        "import_from_backup" = [System.IO.Path]::Combine($gpo_base_path, "GroupPolicy")
        "import_machine" = [System.IO.Path]::Combine($gpo_base_path, "GroupPolicy", "Machine")
        "import_user" = [System.IO.Path]::Combine($gpo_base_path, "GroupPolicy", "User")
        "import_admin" = [System.IO.Path]::Combine($gpo_base_path, "GroupPolicyUsers", "S-1-5-32-544", "User")
        "import_non_admin" = [System.IO.Path]::Combine($gpo_base_path, "GroupPolicyUsers", "S-1-5-32-545", "User")
        "import_audit_pol" = ""
        "import_sec_pol" = ""
    }

    switch ($argv.Count) {
        1 {
            if ($argv -match "%(?<env_var>.*)%") { $argv = $argv -replace "%.*%", [System.Environment]::GetEnvironmentVariable($Matches['env_var']) }
        }
        default {
            if ($argv[-1] -match "%(?<env_var>.*)%") { $argv[-1] = $argv[-1] -replace "%.*%", [System.Environment]::GetEnvironmentVariable($Matches['env_var']) }   
        }
    }
    
#endregion

#region Build Arguments
    $fail_template = "Wrong input! Template: 'COMMAND TEMPLATE', got 'COMMAND '$argv''; path '$argv' is reachable - '$(Test-Path $argv -ErrorAction SilentlyContinue)'" 

    switch ($command) {
        "import_from_backup" {
            if (($argv.Count -ne 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue)) { 
                $message = $fail_template -creplace "COMMAND", "/g"
                $message = $message -creplace "TEMPLATE", "<path_to_backup>"
                Fail-Json -obj $result -message $message 
            }
            $arguments = "`"$(Resolve-Path $argv)`""
            $key = "/g"
        }
        "import_machine" {
            if (($argv.Count -ne 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue) -and $($argv -match ".*\.pol$")) { 
                $message = $fail_template -creplace "COMMAND", "/m"
                $message = $message -creplace "TEMPLATE", "<path>/registry.pol"
                Fail-Json -obj $result -message $message 
            }

            $arguments = "`"$(Resolve-Path $argv)`""
            $key = "/m"
        }
        "import_user" {
            if (($argv.Count -eq 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue) -and $($argv -match ".*\.pol$")) { 
                $message = $fail_template -creplace "COMMAND", "/u"
                $message = $message -creplace "TEMPLATE", "<path>/registry.pol"
                Fail-Json -obj $result -message $message 
            }
            elseif (($argv.Count -eq 2) -and !(Test-Path $argv[1] -ErrorAction SilentlyContinue) -and $($argv[1] -match ".*\.pol$")){
                Get-LocalUser -Name $argv[0] -ErrorAction SilentlyContinue
                $user_exists = $?
                if ($user_exists -eq $false) { 
                    $message = $fail_template -creplace ": 'COMMAND", ": '/u:<username>"
                    $message = $message -creplace "COMMAND.*;", "/u:$($argv[0]) '$($argv[1])';"
                    $message = $message -replace "; path.*", "; path '$($argv[1])' is reachable - '$(Test-Path $argv[1] -ErrorAction SilentlyContinue); user '$($argv[0])' exists - '$user_exists'"
                    $message = $message -creplace "TEMPLATE", "<path>/registry.pol"
                    Fail-Json -obj $result -message $message
                }
            }
    
            if ($argv.Count -eq 2) { $key = "/u:$($argv[0])"; $arguments = "`"$(Resolve-Path $argv[1])`"" }
            else { $key = "/u"; $arguments = "`"$(Resolve-Path $argv)`"" }
        }
        "import_admin" {
            if (($argv.Count -ne 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue) -and $($argv -match ".*\.pol$")) { 
                $message = $fail_template -creplace "COMMAND", "/ua"
                $message = $message -creplace "TEMPLATE", "<path>/registry.pol"
                Fail-Json -obj $result -message $message             
            }
    
            $key = "/ua"
            $arguments = "`"$(Resolve-Path $argv)`""
        }
        "import_non_admin" {
            if (($argv.Count -ne 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue) -and $($argv -match ".*\.pol$")) { 
                $message = $fail_template -creplace "COMMAND", "/un"
                $message = $message -creplace "TEMPLATE", "<path>/registry.pol"
                Fail-Json -obj $result -message $message             
            }
    
            $key = "/un"
            $arguments = "`"$(Resolve-Path $argv)`""
        }
        "import_sec_pol" {
            if (($argv.Count -ne 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue) -and $($argv -match ".*\.inf$")) { 
                $message = $fail_template -creplace "COMMAND", "/s"
                $message = $message -creplace "TEMPLATE", "<path>/GptTmpl.inf"
                Fail-Json -obj $result -message $message             
            }
    
            $key = "/s"
            $arguments = "`"$(Resolve-Path $argv)`""
        }
        "import_audit_pol" {
            if (($argv.Count -eq 1) -and !(Test-Path $argv -ErrorAction SilentlyContinue) -and $($argv -match ".*\.csv$")) { 
                $message = $fail_template -creplace "COMMAND", "/a"        
                $message = $message -creplace "TEMPLATE", "<path>/audit.csv"
                Fail-Json -obj $result -message $message
            }
            elseif (($argv.Count -eq 2) -and $argv[1] -ne "c" -and !(Test-Path $argv[1] -ErrorAction SilentlyContinue) -and $($argv[1] -match ".*\.csv$")) {
                $message = $fail_template -creplace "COMMAND", "/ac"
                $message = $message -creplace "TEMPLATE", "<path>/audit.csv"
                $message = $message -creplace "COMMAND.*;", "/ac '$($argv[1])';"
                $message = $message -replace "; path.*", "; path '$($argv[1])' is reachable - '$(Test-Path $argv[1] -ErrorAction SilentlyContinue)"
                Fail-Json -obj $result -message $message
            }
            elseif ($argv.Count -ne 1) { 
                $message = $fail_template -creplace "COMMAND", "/a[c]"
                $message = $message -creplace "TEMPLATE", "<path>/audit.csv"
                Fail-Json -obj $result -message $message
            }
    
            if ($argv.Count -eq 2) { $key = "/ac"; $arguments = "`"$(Resolve-Path $argv[1])`"" }
            else { $key = "/a"; $arguments = "`"$(Resolve-Path $argv)`"" }
        }
    }

    $pinfo.Arguments = [string]::Join(" ", $key, $arguments)
#endregion

#region main execution
    try {
        $proc.StartInfo = $pinfo
        [void]$proc.Start()
    
        $err = $proc.StandardError.ReadToEndAsync()
        $std = @()
        while ($null -ne ($tmpLine = $proc.StandardOutput.ReadLine())) {
            $std += $tmpLine
        }
        $proc.WaitForExit()

        #region ensuring the thing was applied
        if ($proc.ExitCode -ne 0) { throw [System.Exception]::new("Unexpected return code '$($proc.ExitCode)', output '$([string]::join(' ', $std))'") }

        $result.success = $true
        Exit-Json $result
    }
    catch {
        if ($null -ne $err) { Fail-Json -obj $result -message $err }
        else { Fail-Json -obj $result -message $_.Exception } 
    }
#endregion