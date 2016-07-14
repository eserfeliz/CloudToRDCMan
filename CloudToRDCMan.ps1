###########################################################################
#
# NAME: CloudToRDCMan.ps1
#
#        AUTHOR: Leo Hernandez
# MODIFIED FROM: New-RDCManFile.ps1 by Jan Egil Ring (jer@powershell.no)
#
# COMMENT: Script to create a XML-file for use with Microsoft Remote Desktop Connection Manager
#          from Environment.xml file
#
# You have a royalty-free right to use, modify, reproduce, and
# distribute this script file in any way you find useful, provided that
# you agree that the creator, owner above has no warranty, obligations,
# or liability for such use.
#
# VERSION HISTORY:
# 1.0 07.22.2010 - Initial release
#
###########################################################################

#Initial variables
$ipcount = 0
$homedir = "$env:userprofile\My Documents"
$environ = (Import-Clixml $homedir\Environment.xml)
$envxml = New-Object xml
$envxml.Load("$homedir\Environment.xml")
[array]$envhn = @()
[array]$envips = @()
$envservers = @{}
$domain = $environ.DomainNetBiosName
$OutputFile = "$homedir\$domain.rdg"

# Parse XML to populate environment variables
$root = $envxml.Objs.Obj.DCT.En
$node = $root[0].Clone()
$root | Where-Object {$_.Obj.DCT.En -match $node} | ForEach-Object {$envhn += $_.Obj.DCT.En[0].S[1]."#text"; $envips += $_.Obj.DCT.En[2].S[1]."#text"}
foreach ($hn in $envhn) {$hn; $envservers["$hn"] = $envips[$ipcount]; $ipcount += 1}
$inf = @{"License Servers" = $environ.LSCount; "DDCs" = $environ.XDSiteCount; "TS VDAs" = $environ.TSVDACount; "VDAs" = $environ.totalVDACount; "ICA Clients" = $environ.ICAClientCount; "Domain Controllers" = 0}
$srvnamesuffix = @{"License Servers" = "License"; "DDCs" = "DDC"; "TS VDAs" = "TSVDA"; "VDAs" = "VDA"; "ICA Clients" = "ICAClie"; "Domain Controllers" = "DomainC"}
if ($environ.DomainController1) {$inf["Domain Controllers"] = 1}

#Create a template XML
$template = @'
<?xml version="1.0" encoding="utf-8"?>
<RDCMan schemaVersion="1">
  <version>2.2</version>
  <file>
    <properties>
      <name>DefaultFileName</name>
      <expanded>True</expanded>
      <comment />
        <logonCredentials inherit="None">
          <userName>Administrator</userName>
          <domain></domain>
          <password storeAsClearText="False"></password>
        </logonCredentials>
      <connectionSettings inherit="FromParent" />
     <gatewaySettings inherit="FromParent" />
      <remoteDesktop inherit="FromParent" />
      <localResources inherit="FromParent" />
      <securitySettings inherit="FromParent" />
      <displaySettings inherit="FromParent" />
    </properties>
    <group>
      <properties>
        <name>DefaultGroupName</name>
        <expanded>False</expanded>
        <comment />
        <logonCredentials inherit="FromParent" />
        <connectionSettings inherit="FromParent" />
        <gatewaySettings inherit="FromParent" />
        <remoteDesktop inherit="FromParent" />
        <localResources inherit="FromParent" />
        <securitySettings inherit="FromParent" />
        <displaySettings inherit="FromParent" />
      </properties>
      <server>
        <name>DefaultServerIP</name>
        <displayName>DefaultServerDisplayName</displayName>
        <comment />
        <logonCredentials inherit="FromParent" />
        <connectionSettings inherit="FromParent" />
        <gatewaySettings inherit="FromParent" />
        <remoteDesktop inherit="FromParent" />
        <localResources inherit="FromParent" />
        <securitySettings inherit="FromParent" />
        <displaySettings inherit="FromParent" />
      </server>
    </group>
  </file>
</RDCMan>
'@

#Output template to xml-file
$template | Out-File $homedir\RDCMan-template.xml -encoding UTF8

#Load template into XML object
$xml = New-Object xml
$xml.Load("$homedir\RDCMan-template.xml")

#Set file properties
$file = (@($xml.RDCMan.file.properties)[0]).Clone()
$file.name = $domain
$xml.RDCMan.file.properties | Where-Object { $_.Name -eq "DefaultFileName" } | ForEach-Object  { [void]$xml.RDCMan.file.ReplaceChild($file,$_) }

# Intialize template nodes
$grouptmpl = (@($xml.RDCMan.file.group)[0]).Clone()
$servertmpl = (@($xml.RDCMan.file.group.server)[0]).Clone()
$iptmpl = (@($xml.RDCMan.file.group.server)[0].name).Clone()

# Modify XML to conform to environment properties
$vmgroups = @($inf.keys)
foreach ($indvms in $vmgroups) {
  if (($inf[$indvms]) -gt 0) {
#   foreach - if(vms exist)
    $newgroup = $grouptmpl.Clone()
    $newgroup.properties.name = $indvms
    if (($inf[$indvms]) -eq 1) {
#     foreach - if(vms exist) & if(# of vms = 1) - clone server template for group
      $newserver = $servertmpl.Clone()
      $newserver.displayName = $domain + '-' + $srvnamesuffix[$indvms]
      $newgroup.server | Where-Object { $_.Name -eq "DefaultServerIP" } | ForEach-Object  { [void]$newgroup.AppendChild($newserver) }
    } elseif (($inf[$indvms]) -gt 1) {
#     foreach - if(vms exist) & if(# of vms > 1) - loop logic for server name
      for ($i = 1; $i -le $inf[$indvms]; $i++) {
#       foreach - if(vms exist) & if(# of vms > 1) - for(specific vm > 1) - clone server template for specific group
        $newserver = $servertmpl.Clone()
        if ($i -eq 1) {
#         foreach - if(vms exist) & if(# of vms > 1) - for(specific vm = 1) - write server name
          $newserver.displayName = $domain + '-' + $srvnamesuffix[$indvms]
        } else {
#         foreach - if(vms exist) & if(# of vms > 1) - for(specific vm > 1) - write server name and append server number
          $newserver.displayName = $domain + '-' + $srvnamesuffix[$indvms] + $i
        }
#       foreach - if(vms exist) & if(# of vms > 1) - create server in group being processed
        $newgroup.server | Where-Object { $_.Name -eq "DefaultServerIP" } | ForEach-Object  { [void]$newgroup.AppendChild($newserver) }
      }
    }
#   foreach - if(vms exist) - write group node
    $xml.RDCMan.file.properties | Where-Object { $_.Name -eq "$domain" } | ForEach-Object  { [void]$xml.RDCMan.file.AppendChild($newgroup) }
  }
# foreach - Remove default server node
  $xml.SelectNodes("RDCMan/file/group/server") | Where-Object {$_.displayName -match "DefaultServerDisplayName"} | ForEach-Object { [void]$_.ParentNode.RemoveChild($_)}
}

# Remove default group node
$xml.SelectNodes("RDCMan/file/group") | Where-Object {$_.properties.Name -match "DefaultGroupName"} | ForEach-Object { [void]$_.ParentNode.RemoveChild($_)}

# Write IPs to XML
$xml.SelectNodes("RDCMan/file/group/server") | Where-Object {$_.name -eq "DefaultServerIP"} | ForEach-Object {[string]$_.name = $envservers[$_.displayName]}

#Save xml to file
$xml.Save($OutputFile)

#Remove template xml-file
Remove-Item $homedir\RDCMan-template.xml -Force
