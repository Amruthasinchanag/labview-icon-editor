<?xml version='1.0' encoding='UTF-8'?>
<Project Type="Project" LVVersion="21008000">
	<Property Name="NI.LV.All.SaveVersion" Type="Str">21.0</Property>
	<Property Name="NI.LV.All.SourceOnly" Type="Bool">true</Property>
	<Property Name="NI.Project.Description" Type="Str"></Property>
	<Item Name="My Computer" Type="My Computer">
		<Property Name="server.app.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="server.control.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="server.tcp.enabled" Type="Bool">false</Property>
		<Property Name="server.tcp.port" Type="Int">0</Property>
		<Property Name="server.tcp.serviceName" Type="Str">My Computer/VI Server</Property>
		<Property Name="server.tcp.serviceName.default" Type="Str">My Computer/VI Server</Property>
		<Property Name="server.vi.callsEnabled" Type="Bool">true</Property>
		<Property Name="server.vi.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="specify.custom.address" Type="Bool">false</Property>
		<Item Name="G-CLI" Type="Folder">
			<Item Name="PrepareIESource.vi" Type="VI" URL="../PrepareIESource.vi"/>
			<Item Name="RestoreSetupLVSource.vi" Type="VI" URL="../RestoreSetupLVSource.vi"/>
		</Item>
		<Item Name="support" Type="Folder">
			<Item Name="Add dev dist if present.vi" Type="VI" URL="../support/Add dev dist if present.vi"/>
			<Item Name="Add Files to Archive.vi" Type="VI" URL="../support/Add Files to Archive.vi"/>
			<Item Name="Delete Icon Editor from LV Installation.vi" Type="VI" URL="../support/Delete Icon Editor from LV Installation.vi"/>
			<Item Name="GenerateIEDevModeDiagnosticsCode.vi" Type="VI" URL="../GenerateIEDevModeDiagnosticsCode.vi"/>
			<Item Name="Get Paths to Icon Editor Files in LV Installation.vi" Type="VI" URL="../support/Get Paths to Icon Editor Files in LV Installation.vi"/>
			<Item Name="Prompt to Confirm Archival.vi" Type="VI" URL="../support/Prompt to Confirm Archival.vi"/>
			<Item Name="Set LibraryPaths to Include Icon Editor.vi" Type="VI" URL="../support/Set LibraryPaths to Include Icon Editor.vi"/>
		</Item>
		<Item Name="VI Package install actions" Type="Folder">
			<Property Name="NI.SortType" Type="Int">3</Property>
			<Item Name="VIP_Pre-Uninstall Custom Action.vi" Type="VI" URL="../deployment/VIP_Pre-Uninstall Custom Action.vi"/>
			<Item Name="VIP_Post-Install Custom Action.vi" Type="VI" URL="../deployment/VIP_Post-Install Custom Action.vi"/>
			<Item Name="VIP_Post-Uninstall Custom Action.vi" Type="VI" URL="../deployment/VIP_Post-Uninstall Custom Action.vi"/>
			<Item Name="VIP_Pre-Install Custom Action.vi" Type="VI" URL="../deployment/VIP_Pre-Install Custom Action.vi"/>
		</Item>
		<Item Name="Dependencies" Type="Dependencies"/>
		<Item Name="Build Specifications" Type="Build"/>
	</Item>
</Project>
