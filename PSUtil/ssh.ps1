trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
ipmo posh-ssh -Verbose:$false

function New-PsUtilKeyPairs ($Key) {
    if (Test-Path "$Key.pem") {
        Write-Verbose "Skipping as $Key.pem, already present"
        return
    }

    @"
    openssl genrsa -out "$key.pem" 2048
    openssl rsa -in "$key.pem" -pubout > "$key.pub"
    openssl rsa -in "$key.pem" -pubout -outform DER | openssl md5 -c > "$key.fingerprint"
    openssl req -new -key "$key.pem" -out "cert-req.csr" -sha256 -subj "/C=US/ST=WA/L=none/O=none/CN=www.example.com"
    openssl x509 -req -days 1100 -in "cert-req.csr" -signkey "$key.pem" -out "$key.cert"
"@ | Out-File -Encoding ascii "$key.cmd"

    Start-Process "$key.cmd" -Wait

    if (-not (Test-Path "$key.cert") -or 
        -not (Test-Path "$key.pem") -or 
        -not (Test-Path "$key.pub") -or 
        -not (Test-Path "$key.fingerprint")
        ) {
        throw "New-KeyPairs: Error creating keys $Key"
    }
    $pub = cat "$key.pub"
    $pub | where { $_ -notlike '*PUBLIC KEY*'} > "$key.pub"
}


function Add-SSHKnowHosts ($consolelog, $key, $user, $remote, $port = 22) {
    if (-not (Test-Path "$HOME\.ssh" -PathType Container)) {
        throw '.ssh folder not found'
    }

    $lines = $consolelog | where { $_ -like 'ecdsa-sha2-nistp256*' }
    foreach ($line in $lines) {
        Write-Verbose "$line"
        $parts = $line.Split(' ')
        $fingerprint = "$($parts[0]) $($parts[1])"
        $knownhosts = "$HOME\.ssh\known_hosts"
        $found = cat $knownhosts -EA 0 | select-string $fingerprint -SimpleMatch
        Write-Verbose "Found=$found"
        if ($found.Count -eq 0) {
            if ($port -eq 22) {
                "$remote $fingerprint" | Out-File -Encoding ascii -Append  $knownhosts
            } else {
                "[$remote]:$port $fingerprint" | Out-File -Encoding ascii -Append  $knownhosts
            }
            Write-Verbose "Added $fingerprint to $knownhosts"
        }
    }
}

function Invoke-PsUtilSSHCommand ([string]$Key, [string]$User, [string]$remote, [string]$cmd, [string]$Port = 22) {
    Write-Verbose "ssh -o StrictHostKeyChecking=no -i $key $user@$remote -p $port"
    Write-Verbose "Invoke-PsUtilSSHCommand -Key $key -User $user -Remote $remote -Port $port"
    Write-Verbose "Command:`n$cmd"

    $cmd = $cmd.Replace("`r",'')

    $creds = New-Object System.Management.Automation.PSCredential ($User, (new-object System.Security.SecureString))
    $session = New-SSHSession -ComputerName $remote -KeyFile $key -Port $port -Credential $creds -AcceptKey -Force 3>$null
    $ret = Invoke-SSHCommand -Command $cmd -SSHSession $session -TimeOut 600
    $null = Remove-SSHSession $session
    $ret.Output
    if ($ret.ExitStatus -ne 0) {
        throw "ssh error, ExitStatus=$($ret.ExitStatus), Error=$($ret.Error)"
    }
<#
    Write-Verbose "ssh -o StrictHostKeyChecking=no -i $key $user@$remote -p $port $cmd"
    
    #ssh -o StrictHostKeyChecking=no -i $key "$user@$remote" -p $port $cmd 


    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = 'ssh'
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardInput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = @('-o', 'StrictHostKeyChecking=no', '-i', $key, "$user@$remote", '-p', $port)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.StandardInput.Write($cmd.Replace("`r",''))
    $p.StandardInput.Close()
    $p.WaitForExit()
    $stderr = $p.StandardError.ReadToEnd()

    $stderr = $stderr.split("`n",[System.StringSplitOptions]::RemoveEmptyEntries) | where { $_ -notlike '*Permanently added*'}
    if ($p.ExitCode -ne 0) {
        throw "ssh error: ExitCode=$($p.ExitCode) $stderr"
    }
    $p.StandardOutput.ReadToEnd()
    #>
}

#del C:\Users\padisett\.ssh\known_hosts -ea 0
#$a = Invoke-SSHCommand 'c:\keys\test.pem' 'ec2-user' '54.85.221.16' 'ps'
#$a | fl *
