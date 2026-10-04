<#
.SYNOPSIS
    Pester tests for Start-WslContainerDashboard.ps1.

.DESCRIPTION
    Validates script existence, syntax, comment-based help, and parameters for the
    WSL container HTML dashboard / local control server.
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot "..\..\powershell\wslc\Start-WslContainerDashboard.ps1"
}

Describe "Start-WslContainerDashboard" {
    Context "Script Validation" {
        It "Should exist" {
            Test-Path $script:scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script:scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have a synopsis" {
            (Get-Help $script:scriptPath).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have a description" {
            (Get-Help $script:scriptPath).Description | Should -Not -BeNullOrEmpty
        }
    }

    Context "Parameter Validation" {
        It "Should expose Port, RefreshSeconds, NoLaunch, and WslcPath parameters" {
            $params = (Get-Command $script:scriptPath).Parameters.Keys
            $params | Should -Contain 'Port'
            $params | Should -Contain 'RefreshSeconds'
            $params | Should -Contain 'NoLaunch'
            $params | Should -Contain 'WslcPath'
        }

        It "Should constrain Port to a valid range" {
            $attr = (Get-Command $script:scriptPath).Parameters['Port'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $attr.MinRange | Should -Be 1024
            $attr.MaxRange | Should -Be 65535
        }
    }

    Context "Security" {
        It "Should only bind to the loopback address" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'http://127\.0\.0\.1:'
            $content | Should -Not -Match 'http://\+:'
            $content | Should -Not -Match 'http://\*:'
        }

        It "Should restrict actions to an allow-list" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match "allowedOps"
        }

        It "Should validate image references before invoking wslc" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'function get-validatedImageRef'
            $content | Should -Match "'\^/api/imageinspect\`$'"
        }
    }

    Context "Images" {
        It "Should expose an images endpoint with optional details" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match "'\^/api/images\`$'"
            $content | Should -Match 'function get-images'
            $content | Should -Match "QueryString\['details'\]"
        }

        It "Should render an images table in the page" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="irows"'
            $content | Should -Match 'function renderImages'
            $content | Should -Match 'function showImage'
        }
    }

    Context "Create and Pull" {
        It "Should expose run and pull endpoints" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match "'\^/api/run\`$'"
            $content | Should -Match "'\^/api/pull\`$'"
            $content | Should -Match 'function invoke-run'
            $content | Should -Match 'function invoke-pull'
        }

        It "Should validate create/pull inputs against injection" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'function test-imageRef'
            $content | Should -Match 'function test-containerName'
            $content | Should -Match 'function test-publishSpec'
        }

        It "Should render create and pull controls in the page" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="runImage"'
            $content | Should -Match 'function runContainer'
            $content | Should -Match 'id="pullImage"'
            $content | Should -Match 'function pullImage'
        }

        It "Should offer local images as a dropdown on the create form" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'list="imageOptions"'
            $content | Should -Match '<datalist id="imageOptions">'
            $content | Should -Match "getElementById\('imageOptions'\)"
        }

        It "Should prefill fields and gate the command when a local image is selected" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'onchange="onImageSelected\(\)"'
            $content | Should -Match 'function onImageSelected'
            $content | Should -Match 'cmd\.disabled = true'
        }

        It "Should accept an optional container command on create" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="runCmd"'
            $content | Should -Match '\$commandRaw'
        }

        It "Should accept and validate environment variables on create" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="runEnv"'
            $content | Should -Match '\$envRaw'
            $content | Should -Match "Add\('-e'\)"
        }
    }

    Context "Action log" {
        It "Should record actions and expose an actionlog endpoint" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'function add-actionLog'
            $content | Should -Match "'\^/api/actionlog\`$'"
            $content | Should -Match '\$script:actionLog'
        }

        It "Should render an action-log viewer in the page" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="lrows"'
            $content | Should -Match 'function renderLog'
        }
    }

    Context "Remove" {
        It "Should allow removing containers via the action allow-list" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match "allowedOps\s*=\s*@\([^)]*'remove'"
            $content | Should -Match "container remove --force"
        }

        It "Should validate and expose an image-remove endpoint" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match "'\^/api/removeimage\`$'"
            $content | Should -Match 'function invoke-removeImage'
            $content | Should -Match 'wslc rmi --force'
        }

        It "Should render remove controls with confirmation" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'function removeImage'
            $content | Should -Match "op === 'remove'"
        }
    }

    Context "Docker Hub search" {
        It "Should expose a validated search endpoint that proxies Docker Hub" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match "'\^/api/search\`$'"
            $content | Should -Match 'function invoke-search'
            $content | Should -Match 'function test-searchQuery'
            $content | Should -Match 'hub\.docker\.com/v2/search/repositories'
        }

        It "Should render a search box and results in the page" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="searchQ"'
            $content | Should -Match 'function searchImages'
            $content | Should -Match 'id="srows"'
        }

        It "Should offer a registry dropdown covering Docker Hub, Quay, and MCR" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'id="searchRegistry"'
            $content | Should -Match 'quay\.io/api/v1/find/repositories'
            $content | Should -Match 'mcr\.microsoft\.com/v2/_catalog'
            $content | Should -Match "registry -notin @\('dockerhub', 'quay', 'mcr'\)"
        }
    }
}
