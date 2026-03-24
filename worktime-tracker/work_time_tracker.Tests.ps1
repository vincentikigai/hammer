Describe "WorkTimeTracker Utility Functions" {
    BeforeAll {
        # Dot-sourcing the script to load functions into the scope
        . $PSScriptRoot\work_time_tracker.ps1
    }

    Context "Format-Duration" {
        It "formats seconds correctly into HH:mm:ss" {
            Format-Duration 3661 | Should Be "01:01:01"
            Format-Duration 59 | Should Be "00:00:59"
            Format-Duration 3600 | Should Be "01:00:00"
        }
    }

    Context "ConvertTo-Hashtable" {
        It "recursively converts PSCustomObject to Hashtable" {
            $obj = [PSCustomObject]@{
                Name = "Test"
                Meta = [PSCustomObject]@{
                    ID = 123
                }
                Items = @([PSCustomObject]@{ Key = "Value" })
            }
            $hash = ConvertTo-Hashtable $obj
            $hash -is [System.Collections.Hashtable] | Should Be $true
            $hash.Meta -is [System.Collections.Hashtable] | Should Be $true
            $hash.Items[0] -is [System.Collections.Hashtable] | Should Be $true
            $hash.Meta.ID | Should Be 123
        }
    }
}
