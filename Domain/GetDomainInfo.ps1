# GetDomainInfo.ps1
# This script extracts Active Directory information including:
# - FQDN
# - Domain Trusts (Trusted Domain, Trust Direction, Trust Type, Trust Attributes, Trusted Domain Controller, Trust Status, Trust Is OK)
# - Organizational Units (Name, Description, Container)
# - Domain Groups (Name, Description, Members, Member Of, Container)
# - Domain Users (Name, User Logon Name, Description, Given Name, Last Logon, Password Last Set, Member Of, Container, UAC ID)
# - Domain Policies (GPO Name, Description, Scope of Policies)
#
# Note: Ensure the ActiveDirectory and GroupPolicy modules are installed and available.

function Get-DomainInfo {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-Error "ActiveDirectory module is not available."
        return $null
    }
    
    try {
        Import-Module GroupPolicy -ErrorAction Stop
    }
    catch {
        Write-Warning "GroupPolicy module not available. Domain Policies extraction will be limited."
    }

    # -------------------------
    # 1. FQDN of the current domain
    # -------------------------
    try {
        $domainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $FQDN = $domainObj.Name
    }
    catch {
        $FQDN = "N/A"
    }
    
    # -------------------------
    # 2. Domain Trusts
    # -------------------------
    $trustsList = @()
    try {
        $trusts = Get-ADTrust -Filter * -ErrorAction SilentlyContinue
        foreach ($trust in $trusts) {
            $trustedDC = "N/A"
            if ($trust.TrustPartner) {
                try {
                    $dc = Get-ADDomainController -DomainName $trust.TrustPartner -ErrorAction SilentlyContinue
                    if ($dc) { $trustedDC = $dc.Name }
                }
                catch { }
            }
            $trustsList += @{
                "Trusted Domain"          = $trust.TrustPartner
                "Trust Direction"         = $trust.TrustDirection
                "Trust Type"              = $trust.TrustType
                "Trust Attributes"        = $trust.TrustAttributes
                "Trusted Domain Controller" = $trustedDC
                "Trust Status"            = "OK"    # Placeholder; you may add logic to test the trust
                "Trust Is OK"             = "Yes"   # Placeholder
            }
        }
    }
    catch {
        $trustsList = @()
    }
    
    # -------------------------
    # 3. Organizational Units
    # -------------------------
    $ouList = @()
    try {
        $ous = Get-ADOrganizationalUnit -Filter * -Properties Description, DistinguishedName
        foreach ($ou in $ous) {
            $dnParts = $ou.DistinguishedName -split ",",2
            $container = if ($dnParts.Count -gt 1) { $dnParts[1] } else { "N/A" }
            $ouList += @{
                "Name"        = $ou.Name
                "Description" = $ou.Description
                "Container"   = $container
            }
        }
    }
    catch {
        $ouList = @()
    }
    
    # -------------------------
    # 4. Domain Groups
    # -------------------------
    $groupList = @()
    try {
        $groups = Get-ADGroup -Filter * -Properties Description, MemberOf, DistinguishedName
        foreach ($group in $groups) {
            $dnParts = $group.DistinguishedName -split ",",2
            $container = if ($dnParts.Count -gt 1) { $dnParts[1] } else { "N/A" }
            try {
                $members = Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
            }
            catch {
                $members = @()
            }
            $groupList += @{
                "Name"        = $group.Name
                "Description" = $group.Description
                "Members"     = $members
                "Member Of"   = $group.MemberOf
                "Container"   = $container
            }
        }
    }
    catch {
        $groupList = @()
    }
    
    # -------------------------
    # 5. Domain Users
    # -------------------------
    $userList = @()
    try {
        $users = Get-ADUser -Filter * -Properties SamAccountName, Description, GivenName, LastLogonDate, PasswordLastSet, MemberOf, DistinguishedName, userAccountControl
        foreach ($user in $users) {
            $dnParts = $user.DistinguishedName -split ",",2
            $container = if ($dnParts.Count -gt 1) { $dnParts[1] } else { "N/A" }
            $userList += @{
                "Name"              = $user.Name
                "User Logon Name"   = $user.SamAccountName
                "Description"       = $user.Description
                "Given Name"        = $user.GivenName
                "Last Logon"        = $user.LastLogonDate
                "Password Last Set" = $user.PasswordLastSet
                "Member Of"         = $user.MemberOf
                "Container"         = $container
                "UAC ID"            = $user.userAccountControl
            }
        }
    }
    catch {
        $userList = @()
    }
    
    # -------------------------
    # 6. Domain Policies (GPOs)
    # -------------------------
    $gpoList = @()
    try {
        $gpos = Get-GPO -All -ErrorAction SilentlyContinue
        foreach ($gpo in $gpos) {
            $gpoList += @{
                "GPO Name"         = $gpo.DisplayName
                "Description"      = $gpo.Description
                "Scope of Policies"= "Not Implemented"  # Retrieving scope (linked OUs/groups) requires further processing
            }
        }
    }
    catch {
        $gpoList = @()
    }
    
    # -------------------------
    # Combine AD Data into Final Object
    # -------------------------
    $domainInfo = @{
        "FQDN"                 = $FQDN
        "Domain Trusts"        = $trustsList
        "Organizational Units" = $ouList
        "Domain Groups"        = $groupList
        "Domain Users"         = $userList
        "Domain Policies"      = $gpoList
    }
    
    return $domainInfo
}

# Execute the function and output the result for further processing.
$resultObj = Get-DomainInfo
return $resultObj
