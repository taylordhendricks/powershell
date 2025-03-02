@{
    Root = 'Search-FSLogixProfile\Search-FSLogixProfile.ps1'
    OutputPath = 'Search-FSLogixProfile\out'
    Package = @{
        Enabled = $true
        Obfuscate = $false
        HideConsoleWindow = $true
        DotNetVersion = 'v4.6.2'
        FileVersion = '1.0.0'
        FileDescription = 'Seaerch FSLogix Profiles | Tool to search FSLogix Profiles when FlipFlop is not enabled'
        ProductName = 'Search FSLogix Profiles'
        ProductVersion = '0.1'
        Copyright = ''
        RequireElevation = $false
        ApplicationIconPath = 'icon.ico'
        PackageType = 'Console'
        Resources = [string[]]@("icon.ico")
    }
    Bundle = @{
        Enabled = $true
        Modules = $true
        # IgnoredModules = @()
    }
}
        