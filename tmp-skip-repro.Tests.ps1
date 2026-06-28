BeforeDiscovery {
    $script:ghReady = $false
}
Describe 'Integration' -Tag 'Integration' {
    It 'Should block' -Skip:(-not $script:ghReady) {
        $true | Should -Be $false
    }
}
